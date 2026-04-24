import { Outlet } from "react-router-dom";
import Sidebar from "./Sidebar";
import RightPanel from "./RightPanel";

function AppShell() {
  return (
    <div className="flex h-screen overflow-hidden bg-white text-gray-900">
      <Sidebar />
      <main className="flex-1 overflow-y-auto">
        <Outlet />
      </main>
      <RightPanel />
    </div>
  );
}

export default AppShell;
