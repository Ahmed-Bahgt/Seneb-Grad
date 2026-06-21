import React, { useState } from 'react';
import { 
  format, 
  startOfMonth, 
  endOfMonth, 
  startOfWeek, 
  endOfWeek, 
  eachDayOfInterval, 
  isSameMonth, 
  isSameDay, 
  addMonths, 
  subMonths 
} from 'date-fns';
import { 
  ChevronLeft, 
  ChevronRight, 
  Plus, 
  Clock, 
  MapPin,
  Filter,
  Users,
  Calendar as CalendarIcon
} from 'lucide-react';
import { cn } from '../lib/utils';
import { mockAppointments, mockPatients, mockUsers } from '../data/mockData';
import { motion, AnimatePresence } from 'motion/react';

export const CalendarPage: React.FC = () => {
  const [currentDate, setCurrentDate] = useState(new Date());
  const [selectedDate, setSelectedDate] = useState(new Date());

  const monthStart = startOfMonth(currentDate);
  const monthEnd = endOfMonth(monthStart);
  const startDate = startOfWeek(monthStart);
  const endDate = endOfWeek(monthEnd);

  const days = eachDayOfInterval({
    start: startDate,
    end: endDate,
  });

  const nextMonth = () => setCurrentDate(addMonths(currentDate, 1));
  const prevMonth = () => setCurrentDate(subMonths(currentDate, 1));

  const appointmentsForSelectedDate = mockAppointments.filter(apt => 
    isSameDay(new Date(apt.date), selectedDate)
  );

  return (
    <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 h-[calc(100vh-10rem)]">
      {/* Calendar Section */}
      <div className="lg:col-span-8 bg-white dark:bg-slate-900 rounded-3xl border border-slate-200 dark:border-slate-800 flex flex-col overflow-hidden">
        <div className="p-8 border-b border-slate-100 dark:border-slate-800 flex items-center justify-between">
          <div className="flex items-center gap-6">
            <h2 className="text-2xl font-black text-slate-900 dark:text-white capitalize">
              {format(currentDate, 'MMMM yyyy')}
            </h2>
            <div className="flex gap-2">
              <button onClick={prevMonth} className="p-2 hover:bg-slate-50 dark:hover:bg-slate-800 rounded-xl transition-colors">
                <ChevronLeft size={20} />
              </button>
              <button onClick={nextMonth} className="p-2 hover:bg-slate-50 dark:hover:bg-slate-800 rounded-xl transition-colors">
                <ChevronRight size={20} />
              </button>
            </div>
          </div>
          <div className="flex gap-3">
            <button className="flex items-center gap-2 px-4 py-2 bg-slate-50 dark:bg-slate-800 text-slate-600 font-bold rounded-xl text-sm transition-all hover:bg-slate-100">
              <Filter size={16} /> Filters
            </button>
            <button className="flex items-center gap-2 px-6 py-2 bg-indigo-600 text-white font-bold rounded-xl text-sm transition-all shadow-lg shadow-indigo-600/20 hover:bg-indigo-700">
              <Plus size={16} /> Add Event
            </button>
          </div>
        </div>

        <div className="flex-1 grid grid-cols-7">
          {['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map(day => (
            <div key={day} className="py-4 text-center text-xs font-black text-slate-400 uppercase tracking-widest border-b border-slate-50 dark:border-slate-800">
              {day}
            </div>
          ))}
          {days.map((day, idx) => {
            const isToday = isSameDay(day, new Date());
            const isCurrentMonth = isSameMonth(day, monthStart);
            const isSelected = isSameDay(day, selectedDate);
            const appointmentsCount = mockAppointments.filter(apt => isSameDay(new Date(apt.date), day)).length;

            return (
              <div
                key={day.toString()}
                onClick={() => setSelectedDate(day)}
                className={cn(
                  "relative h-32 p-3 border-r border-b border-slate-50 dark:border-slate-800 cursor-pointer transition-all hover:bg-slate-50 dark:hover:bg-slate-800/50",
                  !isCurrentMonth && "opacity-30 bg-slate-50/50 dark:bg-transparent",
                  isSelected && "bg-indigo-50/50 dark:bg-indigo-500/5 ring-2 ring-inset ring-indigo-500/20"
                )}
              >
                <div className="flex justify-between items-start">
                  <span className={cn(
                    "w-8 h-8 flex items-center justify-center rounded-xl text-sm font-bold",
                    isToday ? "bg-indigo-600 text-white" : "text-slate-700 dark:text-slate-300",
                    isSelected && !isToday && "text-indigo-600 font-black"
                  )}>
                    {format(day, 'd')}
                  </span>
                  {appointmentsCount > 0 && (
                    <div className="w-1.5 h-1.5 rounded-full bg-amber-500"></div>
                  )}
                </div>
                
                <div className="mt-2 space-y-1">
                  {mockAppointments.filter(apt => isSameDay(new Date(apt.date), day)).slice(0, 2).map(apt => (
                    <div key={apt.id} className="text-[10px] font-bold px-2 py-1 bg-white dark:bg-slate-800 border border-slate-100 dark:border-slate-700 rounded-lg text-slate-600 dark:text-slate-400 truncate shadow-sm">
                      {format(new Date(apt.date), 'HH:mm')} {mockPatients.find(p => p.id === apt.patientId)?.name.split(' ')[0]}
                    </div>
                  ))}
                  {appointmentsCount > 2 && (
                    <p className="text-[9px] font-black text-indigo-500 pl-1">+{appointmentsCount - 2} more</p>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Daily Agenda Section */}
      <div className="lg:col-span-4 flex flex-col gap-6">
        <motion.div 
          key={selectedDate.toString()}
          initial={{ opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          className="bg-white dark:bg-slate-900 p-8 rounded-3xl border border-slate-200 dark:border-slate-800 flex-1 overflow-y-auto"
        >
          <div className="flex items-center justify-between mb-8">
            <div>
              <p className="text-xs font-black text-indigo-500 uppercase tracking-widest mb-1">{format(selectedDate, 'EEEE')}</p>
              <h3 className="text-xl font-black text-slate-900 dark:text-white">{format(selectedDate, 'MMMM d, yyyy')}</h3>
            </div>
            <div className="w-10 h-10 rounded-2xl bg-slate-100 dark:bg-slate-800 flex items-center justify-center text-slate-400">
              {appointmentsForSelectedDate.length}
            </div>
          </div>

          <div className="space-y-6">
            {appointmentsForSelectedDate.length > 0 ? (
              appointmentsForSelectedDate.map((apt) => {
                const patient = mockPatients.find(p => p.id === apt.patientId);
                const therapist = mockUsers.find(u => u.id === apt.therapistId);
                
                return (
                  <div key={apt.id} className="relative pl-6 group">
                    <div className="absolute left-0 top-0 w-1 h-full bg-slate-100 dark:bg-slate-800 rounded-full group-hover:bg-indigo-500 transition-colors"></div>
                    <div className="space-y-3">
                      <div className="flex items-center justify-between">
                        <span className="text-xs font-black text-slate-400 flex items-center gap-1.5">
                          <Clock size={12} /> {format(new Date(apt.date), 'HH:mm')} - {format(new Date(new Date(apt.date).getTime() + 3600000), 'HH:mm')}
                        </span>
                        <div className={cn(
                          "px-2 py-0.5 rounded-lg text-[10px] font-bold uppercase",
                          apt.type === 'initial' ? "bg-amber-100 text-amber-600" : "bg-blue-100 text-blue-600"
                        )}>
                          {apt.type}
                        </div>
                      </div>
                      
                      <div className="p-4 bg-slate-50 dark:bg-slate-800/50 rounded-2xl border border-transparent hover:border-indigo-100 transition-all cursor-pointer">
                        <h4 className="text-sm font-black text-slate-900 dark:text-white mb-2">{patient?.name}</h4>
                        <div className="flex items-center gap-4">
                          <div className="flex items-center gap-1.5 text-xs text-slate-500 font-medium">
                            <MapPin size={12} /> Room 302
                          </div>
                          <div className="flex items-center gap-1.5 text-xs text-slate-500 font-medium">
                            <Users size={12} /> {therapist?.name.split(' ')[1]}
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                );
              })
            ) : (
              <div className="py-20 text-center">
                <div className="w-12 h-12 bg-slate-50 dark:bg-slate-800 rounded-full flex items-center justify-center mx-auto mb-4 text-slate-300">
                  <CalendarIcon size={24} />
                </div>
                <p className="text-sm font-bold text-slate-400">No appointments scheduled</p>
              </div>
            )}
          </div>
        </motion.div>

        {/* Small Action Card */}
        <div className="bg-indigo-600 p-8 rounded-3xl text-white relative overflow-hidden group">
          <div className="relative z-10">
            <h4 className="text-lg font-black mb-1">Quick Add</h4>
            <p className="text-sm text-indigo-100 mb-6">Create a new therapy session in seconds.</p>
            <button className="w-full py-3 bg-white text-indigo-600 font-bold rounded-2xl flex items-center justify-center gap-3 transition-transform active:scale-95">
              <Plus size={18} /> New Appointment
            </button>
          </div>
          <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-64 h-64 bg-indigo-500 rounded-full opacity-20 blur-3xl group-hover:scale-150 transition-transform duration-1000"></div>
        </div>
      </div>
    </div>
  );
};
