using System;
using System.Runtime.InteropServices;

namespace CodexMode {
    // Public Windows Shell property-store API; no resident notification activator.
    [StructLayout(LayoutKind.Sequential)]
    struct PropertyKey { public Guid Format; public uint Id; }
    [StructLayout(LayoutKind.Explicit)]
    struct PropVariant {
        [FieldOffset(0)] public ushort Type;
        [FieldOffset(8)] public IntPtr Pointer;
        [FieldOffset(16)] private IntPtr Padding;
    }
    [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore {
        void GetCount(out uint count);
        void GetAt(uint index, out PropertyKey key);
        void GetValue(ref PropertyKey key, out PropVariant value);
        void SetValue(ref PropertyKey key, ref PropVariant value);
        void Commit();
    }
    public static class NativeShortcut {
        [DllImport("shell32.dll", CharSet=CharSet.Unicode, PreserveSig=false)]
        static extern void SHGetPropertyStoreFromParsingName(string path, IntPtr bindContext,
            uint flags, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);

        [DllImport("ole32.dll")]
        static extern int PropVariantClear(ref PropVariant value);

        public static string GetAppId(string path) {
            Guid iid = new Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99");
            IPropertyStore store;
            SHGetPropertyStoreFromParsingName(path, IntPtr.Zero, 0, ref iid, out store);
            var key = new PropertyKey { Format = new Guid("9f4c2855-9f79-4b39-a8d0-e1d42de1d5f3"), Id = 5 };
            PropVariant value = new PropVariant();
            try {
                store.GetValue(ref key, out value);
                return value.Type == 31 ? Marshal.PtrToStringUni(value.Pointer) : null;
            } finally { PropVariantClear(ref value); Marshal.ReleaseComObject(store); }
        }

        public static void Create(string path, string executable, string arguments, string appId) {
            object shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell", true));
            object shortcut = null;
            try {
                shortcut = shell.GetType().InvokeMember("CreateShortcut", System.Reflection.BindingFlags.InvokeMethod,
                    null, shell, new object[] { path });
                Type type = shortcut.GetType();
                type.InvokeMember("TargetPath", System.Reflection.BindingFlags.SetProperty, null, shortcut, new object[] { executable });
                type.InvokeMember("Arguments", System.Reflection.BindingFlags.SetProperty, null, shortcut, new object[] { arguments });
                type.InvokeMember("Description", System.Reflection.BindingFlags.SetProperty, null, shortcut, new object[] { "Codex Mode Switcher" });
                type.InvokeMember("Save", System.Reflection.BindingFlags.InvokeMethod, null, shortcut, null);
            } finally {
                if (shortcut != null) Marshal.ReleaseComObject(shortcut);
                Marshal.ReleaseComObject(shell);
            }
            Guid iid = new Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99");
            IPropertyStore store;
            SHGetPropertyStoreFromParsingName(path, IntPtr.Zero, 2, ref iid, out store);
            var key = new PropertyKey { Format = new Guid("9f4c2855-9f79-4b39-a8d0-e1d42de1d5f3"), Id = 5 };
            var value = new PropVariant { Type = 31, Pointer = Marshal.StringToCoTaskMemUni(appId) };
            try { store.SetValue(ref key, ref value); store.Commit(); }
            finally { Marshal.FreeCoTaskMem(value.Pointer); Marshal.ReleaseComObject(store); }
        }
    }
}
