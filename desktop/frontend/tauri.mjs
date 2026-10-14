// `npm run tauri ...`: the Tauri CLI, pointed at the desktop app in
// ../backend/app (it only looks under the current folder by itself).
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

process.env.TAURI_APP_PATH ??= fileURLToPath(new URL("../backend/app", import.meta.url));
process.env.TAURI_FRONTEND_PATH ??= fileURLToPath(new URL(".", import.meta.url));

const cli = createRequire(import.meta.url)("@tauri-apps/cli");
cli.run(process.argv.slice(2), "npm run tauri").catch((err) => {
  cli.logError(err.message);
  process.exit(1);
});
