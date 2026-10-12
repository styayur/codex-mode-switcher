using System;
using System.Runtime.InteropServices;

namespace CodexMode {
    // Documented Windows Store activation contract. No Codex internal API.
    [ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IApplicationActivationManager {
        [PreserveSig] int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string appId,
            [MarshalAs(UnmanagedType.LPWStr)] string arguments, uint options, out uint processId);
        [PreserveSig] int ActivateForFile(IntPtr appId, IntPtr items, IntPtr verb, out uint processId);
        [PreserveSig] int ActivateForProtocol(IntPtr appId, IntPtr items, out uint processId);
    }
    public static class WindowsActivation {
        public static uint Activate(string appId) {
            var type = Type.GetTypeFromCLSID(new Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C"), true);
            object instance = Activator.CreateInstance(type);
            try {
                uint processId;
                int hr = ((IApplicationActivationManager)instance).ActivateApplication(appId, null, 2, out processId);
                Marshal.ThrowExceptionForHR(hr);
                return processId;
            } finally { Marshal.ReleaseComObject(instance); }
        }
    }
}
