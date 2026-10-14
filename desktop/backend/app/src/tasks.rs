//! Task commands for the Tasks page and meeting pages.

use tauri::{AppHandle, Emitter, State};

use voicedesk_core::rules::required_text;

use crate::{err, CmdResult, Shared};
use crate::db::{NewTask, Task};

#[tauri::command]
pub fn list_tasks(st: State<Shared>, meeting_id: Option<i64>) -> CmdResult<Vec<Task>> {
    st.db.tasks(meeting_id).map_err(err)
}

/// Tasks not done yet (the count beside "My tasks").
#[tauri::command]
pub fn open_task_count(st: State<Shared>) -> CmdResult<usize> {
    Ok(st.db.tasks(None).map_err(err)?.iter().filter(|t| !t.done).count())
}

#[tauri::command]
pub fn set_task_done(st: State<Shared>, id: i64, done: bool) -> CmdResult<()> {
    st.db.set_task_done(id, done).map_err(err)
}

#[tauri::command]
pub fn update_task(app: AppHandle, st: State<Shared>, id: i64, description: String, due: Option<String>) -> CmdResult<()> {
    let description = required_text(&description, "A task")?;
    let due = due.filter(|d| !d.trim().is_empty());
    st.db.update_task(id, &description, due.as_deref()).map_err(err)?;
    let _ = app.emit("tasks-changed", ());
    Ok(())
}

#[tauri::command]
pub fn add_task(st: State<Shared>, meeting_id: Option<i64>, description: String, due: Option<String>) -> CmdResult<()> {
    let description = required_text(&description, "A task")?;
    let due = due.filter(|d| !d.trim().is_empty());
    st.db
        .add_task(meeting_id, &NewTask { description, assigned_by: Some("Self".into()), due, quote: None })
        .map_err(err)
}

#[tauri::command]
pub fn delete_task(app: AppHandle, st: State<Shared>, id: i64) -> CmdResult<()> {
    st.db.delete_task(id).map_err(err)?;
    let _ = app.emit("tasks-changed", ());
    Ok(())
}

/// The tasks in their new order. Only open tasks move; done ones keep their places.
#[tauri::command]
pub fn reorder_tasks(app: AppHandle, st: State<Shared>, ids: Vec<i64>) -> CmdResult<()> {
    let done: std::collections::HashSet<i64> = st.db.tasks(None).map_err(err)?.into_iter().filter(|t| t.done).map(|t| t.id).collect();
    let ids: Vec<i64> = ids.into_iter().filter(|id| !done.contains(id)).collect();
    st.db.reorder_tasks(&ids).map_err(err)?;
    let _ = app.emit("tasks-changed", ());
    Ok(())
}
