import React, { useState } from 'react';
import { Sidebar } from './Sidebar';
import { cn } from '../../lib/utils';
import { Bell, Search, User, Moon, Sun } from 'lucide-react';
import { mockUsers } from '../../data/mockData';

interface DashboardLayoutProps {
  children: React.ReactNode;
}

export const DashboardLayout: React.FC<DashboardLayoutProps> = ({ children }) => {
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [darkMode, setDarkMode] = useState(false);
  const currentUser = mockUsers[0];

  return (
    <div className={cn("min-h-screen bg-slate-50 flex transition-colors duration-300", darkMode && "dark bg-slate-950")}>
      <Sidebar collapsed={sidebarCollapsed} setCollapsed={setSidebarCollapsed} />
      
      <div className={cn(
        "flex-1 flex flex-col transition-all duration-300",
        sidebarCollapsed ? "ml-20" : "ml-64"
      )}>
        <header className="h-20 bg-white dark:bg-slate-900 border-b border-slate-200 dark:border-slate-800 sticky top-0 z-40 px-8 flex items-center justify-between">
          <div className="relative w-96 max-w-[50%] group">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 group-focus-within:text-sky-600 transition-colors" />
            <input 
              type="text" 
              placeholder="Search patients, appointments, exercises..."
              className="w-full bg-slate-50 dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg py-2 pl-10 pr-4 text-xs font-medium focus:ring-2 focus:ring-sky-600/10 transition-all outline-none"
            />
          </div>

          <div className="flex items-center gap-4">
            <button 
              onClick={() => setDarkMode(!darkMode)}
              className="p-2 text-slate-500 hover:bg-slate-50 dark:hover:bg-slate-800 rounded-lg transition-colors border border-transparent hover:border-slate-200"
            >
              {darkMode ? <Sun size={18} /> : <Moon size={18} />}
            </button>
            <button className="p-2 text-slate-500 hover:bg-slate-50 dark:hover:bg-slate-800 rounded-lg transition-colors relative border border-transparent hover:border-slate-200">
              <Bell size={18} />
              <span className="absolute top-1.5 right-1.5 w-1.5 h-1.5 bg-red-500 rounded-full border-2 border-white dark:border-slate-900"></span>
            </button>
            
            <div className="h-8 w-px bg-slate-200 dark:border-slate-800 mx-2"></div>

            <div className="flex items-center gap-3">
              <div className="text-right hidden sm:block">
                <p className="text-sm font-bold text-slate-900 dark:text-white leading-none mb-1">Dr. Sarah Miller</p>
                <p className="text-[10px] text-slate-500 font-bold uppercase tracking-wider">{currentUser.role}</p>
              </div>
              <div className="w-10 h-10 rounded-full overflow-hidden bg-slate-200 border-2 border-white shadow-sm">
                <img 
                  referrerPolicy="no-referrer"
                  src="https://api.dicebear.com/7.x/avataaars/svg?seed=Felix" 
                  alt="avatar"
                  className="w-full h-full object-cover"
                />
              </div>
            </div>
          </div>
        </header>

        <main className="p-8 pb-12 overflow-x-hidden">
          {children}
        </main>
      </div>
    </div>
  );
};
