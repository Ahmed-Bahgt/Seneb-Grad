import React from 'react';
import { 
  Users, 
  Calendar, 
  TrendingUp, 
  CheckCircle2, 
  ArrowUpRight, 
  ArrowDownRight,
  Loader2,
  Clock,
  MoreVertical
} from 'lucide-react';
import { cn } from '../lib/utils';
import { 
  BarChart, 
  Bar, 
  XAxis, 
  YAxis, 
  CartesianGrid, 
  Tooltip, 
  ResponsiveContainer, 
  LineChart, 
  Line,
  AreaChart,
  Area
} from 'recharts';
import { mockPatients, mockAppointments } from '../data/mockData';
import { motion } from 'motion/react';

const data = [
  { name: 'Mon', appointments: 12, completion: 85 },
  { name: 'Tue', appointments: 19, completion: 70 },
  { name: 'Wed', appointments: 15, completion: 90 },
  { name: 'Thu', appointments: 22, completion: 80 },
  { name: 'Fri', appointments: 18, completion: 95 },
  { name: 'Sat', appointments: 5, completion: 100 },
];

const patientData = [
  { month: 'Jan', active: 45, new: 12 },
  { month: 'Feb', active: 52, new: 15 },
  { month: 'Mar', active: 48, new: 10 },
  { month: 'Apr', active: 61, new: 18 },
  { month: 'May', active: 55, new: 14 },
  { month: 'Jun', active: 67, new: 22 },
];

export const DashboardPage: React.FC = () => {
  const activePatients = mockPatients.filter(p => p.status === 'active').length;
  const avgSatisfaction = (mockPatients.reduce((acc, p) => acc + p.satisfaction, 0) / mockPatients.length).toFixed(1);

  return (
    <div className="flex flex-col h-[calc(100vh-10rem)]">
      <header className="flex justify-between items-center mb-6">
        <div>
          <h1 className="text-2xl font-bold text-slate-900 dark:text-white">Morning, Sarah</h1>
          <p className="text-slate-500 text-sm italic">You have 8 appointments scheduled for today.</p>
        </div>
        <div className="flex gap-3">
          <button className="px-4 py-2 bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-lg text-sm font-medium shadow-sm hover:bg-slate-50 transition-colors">Export CSV</button>
          <button className="px-4 py-2 bg-sky-600 text-white rounded-lg text-sm font-medium shadow-sm shadow-sky-100 dark:shadow-none hover:bg-sky-700 transition-all">+ New Patient</button>
        </div>
      </header>

      {/* Bento Grid Layout */}
      <div className="grid grid-cols-12 grid-rows-6 gap-4 flex-1">
        
        {/* Active Patients Stats */}
        <div className="col-span-3 row-span-1 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl p-4 flex flex-col justify-center shadow-sm">
          <div className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-1">Active Patients</div>
          <div className="text-3xl font-bold dark:text-white">{activePatients}</div>
          <div className="text-xs text-green-500 font-medium mt-1">+12% from last month</div>
        </div>

        {/* Adherence Stats */}
        <div className="col-span-3 row-span-1 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl p-4 flex flex-col justify-center shadow-sm">
          <div className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-1">Exercise Adherence</div>
          <div className="text-3xl font-bold dark:text-white">82%</div>
          <div className="w-full bg-slate-100 dark:bg-slate-800 h-1.5 rounded-full mt-2">
            <div className="bg-sky-500 h-full rounded-full w-[82%]"></div>
          </div>
        </div>

        {/* Upcoming Schedule (Primary Component) */}
        <div className="col-span-6 row-span-3 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl p-6 shadow-sm flex flex-col overflow-hidden">
          <div className="flex justify-between items-center mb-6">
            <h3 className="font-bold text-slate-800 dark:text-white">Upcoming Schedule</h3>
            <button className="text-sky-600 text-xs font-bold uppercase hover:underline">View Calendar</button>
          </div>
          <div className="space-y-3 overflow-y-auto pr-1">
            {mockAppointments.map((apt) => {
              const patient = mockPatients.find(p => p.id === apt.patientId);
              return (
                <div key={apt.id} className="flex items-center p-3 bg-slate-50 dark:bg-slate-800/50 rounded-xl border border-slate-100 dark:border-slate-700 hover:border-sky-200 transition-colors cursor-pointer group">
                  <div className="w-10 h-10 bg-sky-100 dark:bg-sky-900/40 text-sky-700 dark:text-sky-400 rounded-lg flex items-center justify-center font-bold text-xs mr-4 transition-colors group-hover:bg-sky-600 group-hover:text-white">
                    {new Date(apt.date).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false })}
                  </div>
                  <div className="flex-1">
                    <div className="text-sm font-bold text-slate-900 dark:text-white">{patient?.name}</div>
                    <div className="text-xs text-slate-500">{patient?.injuryType}</div>
                  </div>
                  <div className={cn(
                    "px-2 py-1 text-[10px] rounded uppercase font-bold tracking-tight",
                    apt.type === 'initial' ? "bg-green-100 text-green-700" : 
                    apt.type === 'follow-up' ? "bg-amber-100 text-amber-700" : "bg-sky-100 text-sky-700"
                  )}>
                    {apt.type}
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Patient Satisfaction */}
        <div className="col-span-3 row-span-2 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl p-5 shadow-sm flex flex-col">
          <h3 className="font-bold text-slate-800 dark:text-white text-sm mb-4">Patient Satisfaction</h3>
          <div className="flex-1 flex flex-col items-center justify-center">
            <div className="text-4xl font-black text-sky-600">{avgSatisfaction}</div>
            <div className="flex gap-1 text-sky-500 mt-2">
              {[...Array(5)].map((_, i) => (
                <span key={i} className={i < Math.floor(Number(avgSatisfaction)) ? "text-sky-500" : "text-slate-200"}>★</span>
              ))}
            </div>
            <div className="text-xs text-slate-400 mt-4 text-center">Based on {mockPatients.length} active patients</div>
          </div>
        </div>

        {/* AI Quick Task (In-Grid Assistant) */}
        <div className="col-span-3 row-span-2 bg-sky-900 text-white border border-sky-800 rounded-2xl p-5 shadow-sm flex flex-col relative overflow-hidden group">
          <div className="z-10 relative h-full flex flex-col">
            <h3 className="font-bold text-sm mb-2">Seneb Assistant</h3>
            <p className="text-xs text-sky-200 mb-4 leading-relaxed line-clamp-2">Need help with a treatment plan for cervical radiculopathy?</p>
            <div className="mt-auto">
              <input 
                type="text" 
                placeholder="Ask anything..." 
                className="w-full bg-sky-800 border-none rounded-lg p-2.5 text-xs placeholder-sky-400 focus:ring-1 focus:ring-sky-500 outline-none"
              />
            </div>
          </div>
          <div className="absolute -right-4 -bottom-4 w-24 h-24 bg-sky-500 opacity-20 rounded-full group-hover:scale-150 transition-transform duration-700"></div>
        </div>

        {/* Recent Messages (Bento) */}
        <div className="col-span-6 row-span-3 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl p-6 shadow-sm flex flex-col overflow-hidden">
          <div className="flex justify-between items-center mb-6">
            <h3 className="font-bold text-slate-800 dark:text-white">Recent Messages</h3>
            <div className="flex -space-x-2">
              <div className="w-6 h-6 rounded-full bg-slate-300 border-2 border-white shadow-sm overflow-hidden">
                <img src="https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=50&h=50&fit=crop" alt="" />
              </div>
              <div className="w-6 h-6 rounded-full bg-slate-400 border-2 border-white shadow-sm overflow-hidden text-[8px] flex items-center justify-center font-bold text-white uppercase">EM</div>
              <div className="w-6 h-6 rounded-full bg-sky-500 border-2 border-white flex items-center justify-center text-[10px] font-bold text-white">+3</div>
            </div>
          </div>
          <div className="space-y-4 overflow-y-auto pr-1">
            <div className="flex items-start gap-3">
              <div className="w-8 h-8 rounded-full bg-slate-100 dark:bg-slate-800 flex-shrink-0 flex items-center justify-center text-xs font-bold text-slate-400 uppercase overflow-hidden">
                <img src="https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=50&h=50&fit=crop" alt="" />
              </div>
              <div className="bg-slate-50 dark:bg-slate-800/50 p-3 rounded-2xl rounded-tl-none text-xs leading-relaxed border border-slate-100 dark:border-slate-700 max-w-[80%]">
                <span className="font-bold text-slate-700 dark:text-slate-200 block mb-1 uppercase tracking-tighter text-[10px]">Emma Stone</span>
                Hey Dr. Sarah, I'm feeling some sharp pain during the thoracic extension exercises.
              </div>
            </div>
            <div className="flex items-start gap-3 flex-row-reverse">
              <div className="w-8 h-8 rounded-full bg-sky-100 dark:bg-sky-900/50 flex-shrink-0 flex items-center justify-center text-xs font-bold text-sky-600 uppercase">SB</div>
              <div className="bg-sky-600 text-white p-3 rounded-2xl rounded-tr-none text-xs leading-relaxed max-w-[80%] shadow-lg shadow-sky-600/10">
                Let's stop that exercise immediately. I'll update your plan with a milder stretch.
              </div>
            </div>
          </div>
        </div>

        {/* Exercises Catalog (Bento) */}
        <div className="col-span-6 row-span-2 bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl p-6 shadow-sm overflow-hidden flex flex-col">
           <div className="flex justify-between items-center mb-6">
            <h3 className="font-bold text-slate-800 dark:text-white">Quick Exercise Catalog</h3>
            <div className="flex gap-2">
              <span className="px-2 py-1 bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400 text-[10px] rounded font-bold uppercase tracking-tighter">Cervical</span>
              <span className="px-2 py-1 bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400 text-[10px] rounded font-bold uppercase tracking-tighter">Lumbar</span>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4 flex-1">
            <div className="flex items-center gap-3 p-2 bg-slate-50/50 dark:bg-slate-800/30 border border-slate-100 dark:border-slate-700 rounded-xl hover:border-sky-200 transition-colors cursor-pointer group">
              <div className="w-12 h-12 bg-slate-200 dark:bg-slate-700 rounded-lg overflow-hidden flex-shrink-0 grayscale group-hover:grayscale-0 transition-all">
                <img src="https://images.unsplash.com/photo-1594381898411-846e7d193883?w=50&h=50&fit=crop" alt="" />
              </div>
              <div className="min-w-0">
                <div className="text-[11px] font-bold text-slate-900 dark:text-white truncate">Wall Slides</div>
                <div className="text-[9px] text-slate-400 uppercase font-black tracking-tighter truncate">Scapular Stability</div>
              </div>
            </div>
            <div className="flex items-center gap-3 p-2 bg-slate-50/50 dark:bg-slate-800/30 border border-slate-100 dark:border-slate-700 rounded-xl hover:border-sky-200 transition-colors cursor-pointer group">
              <div className="w-12 h-12 bg-slate-200 dark:bg-slate-700 rounded-lg overflow-hidden flex-shrink-0 grayscale group-hover:grayscale-0 transition-all">
                <img src="https://images.unsplash.com/photo-1566241477600-ac026ad43874?w=50&h=50&fit=crop" alt="" />
              </div>
              <div className="min-w-0">
                <div className="text-[11px] font-bold text-slate-900 dark:text-white truncate">Dead Bug</div>
                <div className="text-[9px] text-slate-400 uppercase font-black tracking-tighter truncate">Core Activation</div>
              </div>
            </div>
          </div>
        </div>

      </div>
    </div>
  );
};

const StatCard = ({ title, value, change, trend, icon: Icon, color }: any) => {
  const colors: any = {
    indigo: 'bg-indigo-50 text-indigo-600 dark:bg-indigo-500/10 dark:text-indigo-400',
    emerald: 'bg-emerald-50 text-emerald-600 dark:bg-emerald-500/10 dark:text-emerald-400',
    amber: 'bg-amber-50 text-amber-600 dark:bg-amber-500/10 dark:text-amber-400',
    blue: 'bg-blue-50 text-blue-600 dark:bg-blue-500/10 dark:text-blue-400',
  };

  return (
    <motion.div 
      initial={{ opacity: 0, scale: 0.95 }}
      animate={{ opacity: 1, scale: 1 }}
      whileHover={{ y: -4 }}
      className="bg-white dark:bg-slate-900 p-6 rounded-3xl border border-slate-200 dark:border-slate-800 shadow-sm"
    >
      <div className="flex items-center justify-between mb-4">
        <div className={cn("p-3 rounded-2xl", colors[color])}>
          <Icon size={24} />
        </div>
        <div className={cn(
          "flex items-center gap-1 text-xs font-bold px-2 py-1 rounded-full",
          trend === 'up' ? "bg-emerald-50 text-emerald-600 dark:bg-emerald-500/10" : "bg-red-50 text-red-600 dark:bg-red-500/10"
        )}>
          {trend === 'up' ? <ArrowUpRight size={14} /> : <ArrowDownRight size={14} />}
          {change}
        </div>
      </div>
      <p className="text-sm font-medium text-slate-500 dark:text-slate-400 mb-1">{title}</p>
      <h4 className="text-2xl font-bold text-slate-900 dark:text-white">{value}</h4>
    </motion.div>
  );
};
