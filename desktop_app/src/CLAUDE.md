# desktop_app/src

## Architecture

- **Router**: react-router-dom v7 with BrowserRouter wrapping in main.tsx, Routes/Route in App.tsx
- **Layout**: AppShell component (three-column: Sidebar 240px | main flex-1 | RightPanel 300px collapsible)
- **Pages**: Dashboard, Issues, History, Settings — each in src/pages/
- **Components**: Shared layout components in src/components/ (Sidebar, RightPanel, AppShell)
- **Styling**: Tailwind CSS v4 via @tailwindcss/vite plugin (no tailwind.config.js)
- **Theme**: Dark theme by default (bg-gray-900, text-gray-100, gray-800 for panels)

## Conventions

- Functional components with default exports
- SVG icons inline in components (no icon library dependency)
- NavLink for active route highlighting in navigation
- Outlet pattern: AppShell renders `<Outlet />` for nested route content
- Panel collapse state is local (useState), not global store

## Dependencies

- react-router-dom: routing (BrowserRouter, Routes, Route, NavLink, Outlet)
- Tailwind CSS v4: utility-first styling via @tailwindcss/vite
- No global state library usage yet (zustand installed but unused)
