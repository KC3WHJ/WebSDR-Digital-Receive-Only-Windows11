// Read-only access to the Windows Core Audio API (documented MMDevice / WASAPI session
// interfaces), loaded by lib/Common.ps1 with Add-Type. It lists audio devices and which
// programs are playing into a device. It never changes any audio setting.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace WebSdrAudio
{
    public class Endpoint
    {
        public string Id;
        public string Name;
        public string Flow;       // "Render" (playback) or "Capture" (recording)
        public override string ToString() { return Name; }
    }

    public class Session
    {
        public int ProcessId;
        public string ProcessName;
        public bool Active;       // true while the program is actually playing
    }

    [StructLayout(LayoutKind.Sequential)]
    struct PropertyKey { public Guid fmtid; public int pid; }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    struct PropVariant
    {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public IntPtr pointer;
    }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
        [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
        [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr client);
        [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection
    {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int Item(int index, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        [PreserveSig] int OpenPropertyStore(int access, out IPropertyStore store);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetState(out int state);
    }

    [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore
    {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int GetAt(int index, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
        [PreserveSig] int Commit();
    }

    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2
    {
        [PreserveSig] int GetAudioSessionControl(IntPtr sessionGuid, int flags, out IntPtr control);
        [PreserveSig] int GetSimpleAudioVolume(IntPtr sessionGuid, int flags, out IntPtr volume);
        [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessions);
        // (notification methods follow; not used)
    }

    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionEnumerator
    {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int GetSession(int index, [MarshalAs(UnmanagedType.IUnknown)] out object session);
    }

    [ComImport, Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl2
    {
        // IAudioSessionControl
        [PreserveSig] int GetState(out int state);
        [PreserveSig] int GetDisplayName(out IntPtr name);
        [PreserveSig] int SetDisplayName(IntPtr name, IntPtr context);
        [PreserveSig] int GetIconPath(out IntPtr path);
        [PreserveSig] int SetIconPath(IntPtr path, IntPtr context);
        [PreserveSig] int GetGroupingParam(out Guid param);
        [PreserveSig] int SetGroupingParam(IntPtr param, IntPtr context);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr client);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr client);
        // IAudioSessionControl2
        [PreserveSig] int GetSessionIdentifier(out IntPtr id);
        [PreserveSig] int GetSessionInstanceIdentifier(out IntPtr id);
        [PreserveSig] int GetProcessId(out int pid);
        [PreserveSig] int IsSystemSoundsSession();
        [PreserveSig] int SetDuckingPreference(bool optOut);
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumeratorCom { }

    public static class Audio
    {
        const int DEVICE_STATE_ACTIVE = 1;
        const int CLSCTX_ALL = 23;
        static PropertyKey FriendlyName = new PropertyKey { fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), pid = 14 };

        [DllImport("ole32.dll")] static extern int PropVariantClear(ref PropVariant pv);

        static IMMDeviceEnumerator NewEnumerator() { return (IMMDeviceEnumerator)new MMDeviceEnumeratorCom(); }

        static string NameOf(IMMDevice dev)
        {
            IPropertyStore store;
            if (dev.OpenPropertyStore(0, out store) != 0) return "";
            PropVariant pv;
            if (store.GetValue(ref FriendlyName, out pv) != 0) return "";
            string name = pv.vt == 31 ? Marshal.PtrToStringUni(pv.pointer) : "";   // 31 = VT_LPWSTR
            PropVariantClear(ref pv);
            return name ?? "";
        }

        static Endpoint Describe(IMMDevice dev, int flow)
        {
            string id; dev.GetId(out id);
            return new Endpoint { Id = id, Name = NameOf(dev), Flow = flow == 0 ? "Render" : "Capture" };
        }

        // flow: 0 = playback devices, 1 = recording devices. Active (enabled, present) devices only.
        public static List<Endpoint> GetEndpoints(int flow)
        {
            var list = new List<Endpoint>();
            IMMDeviceCollection coll;
            if (NewEnumerator().EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE, out coll) != 0) return list;
            int n; coll.GetCount(out n);
            for (int i = 0; i < n; i++)
            {
                IMMDevice dev;
                if (coll.Item(i, out dev) == 0) list.Add(Describe(dev, flow));
            }
            return list;
        }

        // The Windows default device (role 0 = "console", the one Settings > Sound shows), or null.
        public static Endpoint GetDefault(int flow)
        {
            IMMDevice dev;
            if (NewEnumerator().GetDefaultAudioEndpoint(flow, 0, out dev) != 0) return null;
            return Describe(dev, flow);
        }

        // Programs with an audio session on a playback device. Active = playing right now.
        public static List<Session> GetSessions(string endpointId)
        {
            var list = new List<Session>();
            IMMDevice dev;
            if (NewEnumerator().GetDevice(endpointId, out dev) != 0) return list;
            Guid iid = typeof(IAudioSessionManager2).GUID;
            object o;
            if (dev.Activate(ref iid, CLSCTX_ALL, IntPtr.Zero, out o) != 0) return list;
            var mgr = (IAudioSessionManager2)o;
            IAudioSessionEnumerator sessions;
            if (mgr.GetSessionEnumerator(out sessions) != 0) return list;
            int n; sessions.GetCount(out n);
            for (int i = 0; i < n; i++)
            {
                object so;
                if (sessions.GetSession(i, out so) != 0) continue;
                var ctl = so as IAudioSessionControl2;
                if (ctl == null) continue;
                if (ctl.IsSystemSoundsSession() == 0) continue;   // S_OK means it IS the system-sounds session
                int pid, state;
                ctl.GetProcessId(out pid);
                ctl.GetState(out state);
                if (state == 2) continue;                         // expired
                string pname = "";
                try { pname = Process.GetProcessById(pid).ProcessName; } catch (Exception) { continue; }
                list.Add(new Session { ProcessId = pid, ProcessName = pname, Active = state == 1 });
            }
            return list;
        }
    }
}
