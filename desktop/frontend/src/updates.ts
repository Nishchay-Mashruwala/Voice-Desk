import { relaunch } from "@tauri-apps/plugin-process";
import { check } from "@tauri-apps/plugin-updater";
import { toast } from "./toast";

/**
 * Updates come from the project's GitHub releases, signed with Voice Desk's
 * update key (tauri.conf.json -> plugins.updater). `quiet`: say nothing unless
 * there is an update (the startup check).
 */
export async function checkForUpdates(quiet: boolean): Promise<void> {
  try {
    const update = await check();
    if (!update) {
      if (!quiet) toast("Voice Desk is up to date");
      return;
    }
    toast(`Voice Desk ${update.version} is available`, {
      duration: 15000,
      action: {
        label: "Install",
        run: async () => {
          // One toast, updated in place (at most every half second) as the download goes.
          const say = (m: string, duration = 60000) => toast(m, { key: "update", duration });
          say("Downloading the update…");
          let total = 0;
          let done = 0;
          let shown = 0;
          try {
            await update.downloadAndInstall((ev) => {
              if (ev.event === "Started") total = ev.data.contentLength ?? 0;
              else if (ev.event === "Progress") {
                done += ev.data.chunkLength;
                if (total && Date.now() - shown > 500) {
                  shown = Date.now();
                  say(`Downloading the update… ${Math.round((done / total) * 100)}%`);
                }
              } else say("Installing the update…");
            });
            await relaunch();
          } catch (e) {
            say(`Couldn't install the update: ${e}`, 8000);
          }
        },
      },
    });
  } catch (e) {
    // No internet, or no release published yet: only worth saying when asked.
    if (!quiet) toast(`Couldn't check for updates: ${e}`);
  }
}
