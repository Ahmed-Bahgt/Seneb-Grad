import React from 'react';
import { NavLink } from 'react-router-dom';
import { 
  LayoutDashboard, 
  Users, 
  Calendar, 
  Dumbbell, 
  MessageSquare, 
  Settings, 
  LogOut,
  Sparkles,
  ChevronLeft,
  ChevronRight
} from 'lucide-react';
import { cn } from '../../lib/utils';
import { motion } from 'motion/react';

interface SidebarProps {
  collapsed: boolean;
  setCollapsed: (collapsed: boolean) => void;
}

export const Sidebar: React.FC<SidebarProps> = ({ collapsed, setCollapsed }) => {
  const navItems = [
    { icon: LayoutDashboard, label: 'Dashboard', path: '/' },
    { icon: Users, label: 'Patients', path: '/patients' },
    { icon: Calendar, label: 'Schedule', path: '/schedule' },
    { icon: Dumbbell, label: 'Exercises', path: '/exercises' },
    { icon: MessageSquare, label: 'Messages', path: '/messages' },
    { icon: Sparkles, label: 'AI Assistant', path: '/ai-assistant' },
  ];

  return (
    <aside 
      className={cn(
        "fixed left-0 top-0 h-screen bg-white border-r border-slate-200 transition-all duration-300 z-50 flex flex-col",
        collapsed ? "w-20" : "w-64"
      )}
    >
      <div className="p-6 flex items-center justify-between border-b border-slate-100 h-20">
        {!collapsed && (
          <motion.div 
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="font-bold text-xl text-slate-900 flex items-center gap-2"
          >
            <div className="w-8 h-8 bg-sky-600 rounded-lg flex items-center justify-center text-white font-bold">
              S
            </div>
            <span className="tracking-tight">Seneb</span>
          </motion.div>
        )}
        {collapsed && (
          <div className="w-8 h-8 bg-sky-600 rounded-lg flex items-center justify-center text-white font-bold mx-auto">
            S
          </div>
        )}
      </div>

      <nav className="flex-1 px-4 py-6 space-y-1">
        {navItems.map((item) => (
          <NavLink
            key={item.path}
            to={item.path}
            className={({ isActive }) => cn(
              "flex items-center gap-3 px-3 py-2 rounded-md transition-all duration-200 group text-slate-600 hover:bg-slate-50",
              isActive && "bg-sky-50 text-sky-700 font-medium"
            )}
          >
            <item.icon className={cn("w-5 h-5 flex-shrink-0", item.path === '/ai-assistant' && "text-amber-500")} />
            {!collapsed && (
              <motion.span 
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                className="text-sm"
              >
                {item.label}
              </motion.span>
            )}
          </NavLink>
        ))}
      </nav>

      <div className="p-4 mt-auto border-t border-slate-100">
        <div className={cn("flex items-center gap-3 p-2", collapsed && "justify-center")}>
          <div className="w-10 h-10 rounded-full bg-slate-200 border-2 border-white shadow-sm overflow-hidden flex-shrink-0">
            <img src="https://api.dicebear.com/7.x/avataaars/svg?seed=Felix" alt="avatar" />
          </div>
          {!collapsed && (
            <div>
              <div className="text-sm font-bold text-slate-900">Dr. Sarah Miller</div>
              <div className="text-xs text-slate-500 underline">Senior PT</div>
            </div>
          )}
        </div>
      </div>

      <button 
        onClick={() => setCollapsed(!collapsed)}
        className="absolute -right-4 top-1/2 -translate-y-1/2 w-8 h-8 bg-white border border-slate-200 rounded-full flex items-center justify-center shadow-md hover:bg-slate-50 transition-colors z-[60]"
      >
        {collapsed ? <ChevronRight size={16} /> : <ChevronLeft size={16} />}
      </button>
    </aside>
  );
};
