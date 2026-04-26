import { useEffect } from "react";
import { Outlet, useNavigate } from "react-router-dom";
import Sidebar from "./Sidebar";
import { useRunConfigStore } from "../stores/runConfigStore";

async function requestNotificationPermission(notificationsEnabled: boolean) {
  if (!notificationsEnabled) return;
  try {
    const { requestPermission } = await import(
      "@tauri-apps/plugin-notification"
    );
    await requestPermission();
  } catch {
    // Non-Tauri environment or permission already denied — ignore
  }
}

async function syncNotificationPreference(enabled: boolean) {
  try {
    const { invoke } = await import("@tauri-apps/api/core");
    await invoke("set_notification_enabled", { enabled });
  } catch {
    // Non-Tauri environment — ignore
  }
}

async function setupNotificationClickHandler(navigate: ReturnType<typeof useNavigate>) {
  try {
    const { onAction } = await import("@tauri-apps/plugin-notification");
    const { getCurrentWindow } = await import("@tauri-apps/api/window");

    await onAction((notification) => {
      // Bring the app window to the foreground
      const mainWindow = getCurrentWindow();
      mainWindow.show();
      mainWindow.setFocus();

      // Optionally navigate based on notification type
      if (notification.extra) {
        const type = notification.extra["type"] as string | undefined;
        const issueNumber = notification.extra["issue_number"];

        if (type && issueNumber != null) {
          switch (type) {
            case "iteration_complete":
            case "passing_score":
              navigate(`/issues?issue=${issueNumber}`);
              break;
            case "pr_created":
              navigate(`/history?issue=${issueNumber}`);
              break;
            case "run_failure":
              navigate(`/issues?issue=${issueNumber}`);
              break;
          }
        }
      }
    });
  } catch {
    // Non-Tauri environment — ignore
  }
}

function AppShell() {
  const navigate = useNavigate();
  const { notificationsEnabled } = useRunConfigStore();

  useEffect(() => {
    requestNotificationPermission(notificationsEnabled);
    setupNotificationClickHandler(navigate);
  }, [navigate, notificationsEnabled]);

  // Sync notification preference to Rust backend whenever it changes
  useEffect(() => {
    syncNotificationPreference(notificationsEnabled);
  }, [notificationsEnabled]);

  return (
    <div className="flex h-screen overflow-hidden bg-white text-gray-900">
      <Sidebar />
      <main className="flex-1 overflow-y-auto">
        <Outlet />
      </main>
    </div>
  );
}

export default AppShell;
