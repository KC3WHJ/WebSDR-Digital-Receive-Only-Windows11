#!/usr/bin/env python3
"""Pre-configure a CommStat install for receive-only use with a WebSDR.

Run once by install.sh, after CommStat has been cloned. It:

  * creates traffic.db3 from CommStat's own shipped template if there isn't one
    (exactly what CommStat's launcher would do on first run),
  * stores the user's callsign / grid / state, so CommStat starts without
    asking,
  * adds ONE JS8 connector - the local WebSDR JS8Call - with auto-connect on
    and RF Ack OFF. RF Ack is what makes CommStat automatically transmit an
    acknowledgement over the air when it receives a STATREP; there is no
    radio here, and an acknowledgement must never be triggered by traffic
    heard through someone else's receiver.

It never overwrites anything: an existing database keeps its data, and an
existing connector with the same name is left exactly as it is.

Usage: seed_commstat.py COMMSTAT_DIR CALLSIGN GRID STATE RIG_NAME TCP_PORT
"""
import os
import shutil
import sqlite3
import sys


def main(argv):
    if len(argv) != 7:
        sys.exit(__doc__)
    commstat_dir, callsign, grid, state, rig_name, port = argv[1:]
    port = int(port)
    db_path = os.path.join(commstat_dir, "traffic.db3")
    template = os.path.join(commstat_dir, "traffic.db3.template")

    if not os.path.isdir(commstat_dir):
        sys.exit(f"CommStat not found at {commstat_dir}")

    if not os.path.exists(db_path):
        if not os.path.exists(template):
            sys.exit(f"Neither {db_path} nor {template} exists - is this a complete CommStat checkout?")
        shutil.copy(template, db_path)
        print(f"Created {db_path} from CommStat's template.")
    else:
        print(f"Keeping existing {db_path}.")

    # Callsign / grid / state: only fill in what's still blank, so re-running
    # the installer can't overwrite settings the user has since changed in CommStat.
    with sqlite3.connect(db_path, timeout=10) as conn:
        row = conn.execute("SELECT callsign, gridsquare, state FROM controls WHERE id = 1").fetchone()
        if row is None:
            sys.exit("CommStat's database has no 'controls' row - unexpected schema.")
        cur_call, cur_grid, cur_state = (row[0] or "", row[1] or "", row[2] or "")
        conn.execute(
            "UPDATE controls SET callsign = ?, gridsquare = ?, state = ? WHERE id = 1",
            (cur_call or callsign.upper(), cur_grid or grid, cur_state or state.upper()),
        )
        conn.commit()
    print("Callsign/grid/state set (existing values kept).")

    # Use CommStat's own ConnectorManager so validation and defaults are exactly
    # what its JS8 Connectors dialog would produce.
    sys.path.insert(0, commstat_dir)
    os.chdir(commstat_dir)
    from connector_manager import ConnectorManager  # noqa: E402  (needs the path set above)

    mgr = ConnectorManager(db_path)
    existing = [c for c in mgr.get_all_connectors(enabled_only=False) if c.get("rig_name") == rig_name]
    if existing:
        print(f"Connector '{rig_name}' already present - left as it is.")
        return
    ok = mgr.add_connector(
        rig_name=rig_name,
        tcp_port=port,
        server="127.0.0.1",
        state="",
        comment="Receive-only JS8Call fed by a web SDR (no radio, no TX)",
        set_as_default=True,
        auto_connect=True,
        rf_ack=False,
    )
    if not ok:
        sys.exit("CommStat refused to add the connector.")
    print(f"Added connector '{rig_name}' -> 127.0.0.1:{port} (auto-connect on, RF Ack OFF).")


if __name__ == "__main__":
    main(sys.argv)
