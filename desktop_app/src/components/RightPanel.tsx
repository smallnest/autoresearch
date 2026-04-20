import { useState } from "react";

function RightPanel() {
  const [collapsed, setCollapsed] = useState(false);

  return (
    <aside
      className={`h-screen bg-gray-800 border-l border-gray-700 shrink-0 transition-[width] duration-200 ${
        collapsed ? "w-10" : "w-[300px]"
      }`}
    >
      <div className="h-14 flex items-center justify-between px-3 border-b border-gray-700">
        {!collapsed && (
          <span className="text-sm font-medium text-gray-300">Info Panel</span>
        )}
        <button
          onClick={() => setCollapsed(!collapsed)}
          className="p-1.5 rounded hover:bg-gray-700 text-gray-400 hover:text-gray-200 transition-colors"
          aria-label={collapsed ? "Expand panel" : "Collapse panel"}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            className="h-4 w-4"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            {collapsed ? (
              <polyline points="9 18 15 12 9 6" />
            ) : (
              <polyline points="15 18 9 12 15 6" />
            )}
          </svg>
        </button>
      </div>
      {!collapsed && (
        <div className="p-4 text-sm text-gray-400">
          <p>Select an item to view details.</p>
        </div>
      )}
    </aside>
  );
}

export default RightPanel;
