//! Right-clicking Voice Desk's taskbar button shows "Copy last dictation".
//!
//! Windows jump-list tasks launch the app with an argument; the single-instance
//! plugin forwards that to the running app, which does the copy.

pub const COPY_LAST_ARG: &str = "--copy-last-dictation";

#[cfg(windows)]
pub fn install() -> windows::core::Result<()> {
    use windows::core::{Interface, HSTRING};
    use windows::Win32::Storage::EnhancedStorage::PKEY_Title;
    use windows::Win32::System::Com::StructuredStorage::PROPVARIANT;
    use windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED};
    use windows::Win32::UI::Shell::Common::{IObjectArray, IObjectCollection};
    use windows::Win32::UI::Shell::PropertiesSystem::IPropertyStore;
    use windows::Win32::UI::Shell::{
        DestinationList, EnumerableObjectCollection, ICustomDestinationList, IShellLinkW, ShellLink,
    };

    let exe = std::env::current_exe().map_err(|_| windows::core::Error::empty())?;
    let exe = HSTRING::from(exe.as_os_str());
    unsafe {
        // Usually already initialised by the webview; "already initialised" is fine.
        let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED);
        let list: ICustomDestinationList = CoCreateInstance(&DestinationList, None, CLSCTX_INPROC_SERVER)?;
        let mut max_slots = 0u32;
        let _removed: IObjectArray = list.BeginList(&mut max_slots)?;

        let link: IShellLinkW = CoCreateInstance(&ShellLink, None, CLSCTX_INPROC_SERVER)?;
        link.SetPath(&exe)?;
        link.SetArguments(&HSTRING::from(COPY_LAST_ARG))?;
        link.SetIconLocation(&exe, 0)?;
        link.SetDescription(&HSTRING::from("Copy the text of your last dictation"))?;
        let props: IPropertyStore = link.cast()?;
        props.SetValue(&PKEY_Title, &PROPVARIANT::from("Copy last dictation"))?;
        props.Commit()?;

        let tasks: IObjectCollection = CoCreateInstance(&EnumerableObjectCollection, None, CLSCTX_INPROC_SERVER)?;
        tasks.AddObject(&link)?;
        list.AddUserTasks(&tasks.cast::<IObjectArray>()?)?;
        list.CommitList()?;
    }
    Ok(())
}

#[cfg(not(windows))]
pub fn install() -> Result<(), ()> {
    // macOS/Linux have no taskbar jump lists; the tray/menu-bar menu has the same item.
    Ok(())
}
