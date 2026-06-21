import React, { useState } from 'react';
import { 
  Plus, 
  Filter, 
  Search, 
  MoreHorizontal, 
  Phone, 
  Mail, 
  ChevronRight,
  TrendingUp,
  Award,
  Calendar as CalendarIcon,
  Users
} from 'lucide-react';
import { mockPatients, mockUsers } from '../data/mockData';
import { Patient } from '../types';
import { cn } from '../lib/utils';
import { motion, AnimatePresence } from 'motion/react';

export const PatientsPage: React.FC = () => {
  const [selectedPatient, setSelectedPatient] = useState<Patient | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'inactive'>('all');

  const filteredPatients = mockPatients.filter(p => {
    const matchesSearch = p.name.toLowerCase().includes(searchTerm.toLowerCase()) || 
                         p.injuryType.toLowerCase().includes(searchTerm.toLowerCase());
    const matchesStatus = statusFilter === 'all' || p.status === statusFilter;
    return matchesSearch && matchesStatus;
  });

  return (
    <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 h-[calc(100vh-10rem)]">
      {/* List Sidebar */}
      <div className={cn(
        "bg-white dark:bg-slate-900 rounded-3xl border border-slate-200 dark:border-slate-800 flex flex-col transition-all duration-300",
        selectedPatient ? "lg:col-span-4" : "lg:col-span-12"
      )}>
        <div className="p-6 border-b border-slate-100 dark:border-slate-800">
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-xl font-bold text-slate-900 dark:text-white">Patients</h2>
            <button className="bg-indigo-600 hover:bg-indigo-700 text-white p-2 rounded-xl transition-all shadow-lg shadow-indigo-600/20">
              <Plus size={20} />
            </button>
          </div>

          <div className="flex gap-2 mb-4">
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" size={16} />
              <input 
                type="text" 
                placeholder="Search patients..."
                className="w-full bg-slate-50 dark:bg-slate-800 border-none rounded-xl py-2 pl-10 pr-4 text-sm focus:ring-2 focus:ring-indigo-600/20 transition-all outline-none"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
              />
            </div>
            <button className="p-2.5 bg-slate-50 dark:bg-slate-800 rounded-xl text-slate-500 hover:text-indigo-600 transition-colors">
              <Filter size={18} />
            </button>
          </div>

          <div className="flex gap-2">
            {['all', 'active', 'inactive'].map((status) => (
              <button
                key={status}
                onClick={() => setStatusFilter(status as any)}
                className={cn(
                  "px-4 py-1.5 rounded-full text-xs font-bold capitalize transition-all",
                  statusFilter === status 
                    ? "bg-indigo-600 text-white" 
                    : "bg-slate-100 dark:bg-slate-800 text-slate-500 hover:bg-slate-200"
                )}
              >
                {status}
              </button>
            ))}
          </div>
        </div>

        <div className="flex-1 overflow-y-auto p-4 space-y-2">
          {filteredPatients.map((patient) => (
            <button
              key={patient.id}
              onClick={() => setSelectedPatient(patient)}
              className={cn(
                "w-full text-left p-4 rounded-2xl flex items-center gap-4 transition-all group",
                selectedPatient?.id === patient.id 
                  ? "bg-indigo-50 dark:bg-indigo-500/10 border-indigo-100" 
                  : "hover:bg-slate-50 dark:hover:bg-slate-800/50 border-transparent"
              )}
            >
              <div className={cn(
                "w-12 h-12 rounded-2xl flex items-center justify-center font-bold text-lg border-2",
                selectedPatient?.id === patient.id 
                  ? "bg-white border-indigo-200 text-indigo-600" 
                  : "bg-slate-100 border-slate-200 text-slate-500"
              )}>
                {patient.name.charAt(0)}
              </div>
              <div className="flex-1">
                <div className="flex items-center justify-between mb-0.5">
                  <p className={cn(
                    "font-bold text-sm truncate",
                    selectedPatient?.id === patient.id ? "text-indigo-900 dark:text-indigo-200" : "text-slate-900 dark:text-white"
                  )}>
                    {patient.name}
                  </p>
                  <span className={cn(
                    "text-[10px] uppercase font-black px-2 py-0.5 rounded-full",
                    patient.status === 'active' ? "bg-emerald-100 text-emerald-600" : "bg-slate-100 text-slate-500"
                  )}>
                    {patient.status}
                  </span>
                </div>
                <p className="text-xs text-slate-500 font-medium truncate">{patient.injuryType}</p>
              </div>
              <ChevronRight className={cn(
                "w-4 h-4 text-slate-300 transition-transform group-hover:translate-x-1",
                selectedPatient?.id === patient.id && "text-indigo-400"
              )} />
            </button>
          ))}
        </div>
      </div>

      {/* Details View */}
      <AnimatePresence mode="wait">
        {selectedPatient ? (
          <motion.div 
            key={selectedPatient.id}
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: 20 }}
            className="lg:col-span-8 bg-white dark:bg-slate-900 rounded-3xl border border-slate-200 dark:border-slate-800 overflow-y-auto"
          >
            <div className="p-8 border-b border-slate-100 dark:border-slate-800 sticky top-0 bg-white/80 dark:bg-slate-900/80 backdrop-blur-sm z-10 flex items-center justify-between">
              <div className="flex items-center gap-6">
                <div className="w-20 h-20 rounded-3xl bg-indigo-600 flex items-center justify-center text-white text-3xl font-black shadow-xl shadow-indigo-600/30">
                  {selectedPatient.name.charAt(0)}
                </div>
                <div>
                  <h2 className="text-2xl font-black text-slate-900 dark:text-white">{selectedPatient.name}</h2>
                  <div className="flex gap-4 mt-1">
                    <span className="text-sm text-slate-500 font-medium">{selectedPatient.age} years • {selectedPatient.email}</span>
                  </div>
                </div>
              </div>
              <div className="flex gap-3">
                <button className="p-3 bg-slate-100 dark:bg-slate-800 text-slate-600 rounded-2xl hover:bg-slate-200 transition-colors">
                  <Mail size={18} />
                </button>
                <button className="p-3 bg-slate-100 dark:bg-slate-800 text-slate-600 rounded-2xl hover:bg-slate-200 transition-colors">
                  <Phone size={18} />
                </button>
                <button className="bg-indigo-600 text-white px-6 py-3 rounded-2xl font-bold hover:bg-indigo-700 transition-all shadow-lg shadow-indigo-600/20">
                  Edit Profile
                </button>
              </div>
            </div>

            <div className="p-8 grid grid-cols-1 md:grid-cols-2 gap-8">
              {/* Clinical Summary */}
              <div className="space-y-6">
                <section>
                  <h3 className="text-xs uppercase font-black text-slate-400 tracking-widest mb-4">Current Case</h3>
                  <div className="bg-slate-50 dark:bg-slate-800/50 p-6 rounded-3xl border border-slate-100 dark:border-slate-800">
                    <p className="text-sm font-black text-slate-900 dark:text-white mb-2">{selectedPatient.injuryType}</p>
                    <p className="text-sm text-slate-600 dark:text-slate-400 leading-relaxed mb-4">{selectedPatient.injuryDescription}</p>
                    <div className="flex items-center gap-3 p-3 bg-white dark:bg-slate-800 rounded-2xl border border-slate-100 dark:border-slate-700">
                      <div className="w-8 h-8 rounded-full bg-emerald-100 text-emerald-600 flex items-center justify-center">
                        <TrendingUp size={16} />
                      </div>
                      <div>
                        <p className="text-[10px] text-slate-400 font-bold uppercase">Status</p>
                        <p className="text-xs font-bold text-slate-900 dark:text-white">Positive Progression</p>
                      </div>
                    </div>
                  </div>
                </section>

                <section>
                  <h3 className="text-xs uppercase font-black text-slate-400 tracking-widest mb-4">Treatment Plan</h3>
                  <div className="p-6 border-2 border-dashed border-slate-200 dark:border-slate-800 rounded-3xl">
                    <p className="text-sm text-slate-600 dark:text-slate-400 leading-relaxed italic line-clamp-4">
                      "{selectedPatient.treatmentPlan}"
                    </p>
                  </div>
                </section>
              </div>

              {/* Patient Stats & History */}
              <div className="space-y-6">
                <div className="grid grid-cols-2 gap-4">
                  <div className="p-6 bg-indigo-50 dark:bg-indigo-500/10 rounded-3xl border border-indigo-100 dark:border-indigo-900/30">
                    <Award className="text-indigo-600 mb-2" size={24} />
                    <p className="text-2xl font-black text-indigo-900 dark:text-indigo-200">{selectedPatient.adherenceRate}%</p>
                    <p className="text-xs text-indigo-600 font-bold">Adherence Rate</p>
                  </div>
                  <div className="p-6 bg-slate-50 dark:bg-slate-800/50 rounded-3xl border border-slate-100 dark:border-slate-800">
                    <CalendarIcon className="text-slate-600 mb-2" size={24} />
                    <p className="text-lg font-black text-slate-900 dark:text-white">{selectedPatient.lastVisit}</p>
                    <p className="text-xs text-slate-500 font-bold">Last Visit</p>
                  </div>
                </div>

                <section>
                  <h3 className="text-xs uppercase font-black text-slate-400 tracking-widest mb-4">Assigned Therapist</h3>
                  <div className="flex items-center gap-4 p-4 bg-white dark:bg-slate-800 border-2 border-slate-50 dark:border-slate-700 rounded-3xl">
                    <img 
                      className="w-12 h-12 rounded-2xl object-cover"
                      src={mockUsers.find(u => u.id === selectedPatient.assignedTherapistId)?.avatar} 
                      alt=""
                    />
                    <div className="flex-1">
                      <p className="text-sm font-black text-slate-900 dark:text-white">
                        {mockUsers.find(u => u.id === selectedPatient.assignedTherapistId)?.name}
                      </p>
                      <p className="text-xs text-slate-500">Chief Physiotherapist</p>
                    </div>
                    <button className="text-indigo-600 font-bold text-xs hover:underline">Reassign</button>
                  </div>
                </section>

                <div className="bg-slate-900 dark:bg-slate-800 p-6 rounded-3xl text-white">
                  <div className="flex items-center justify-between mb-4">
                    <p className="text-xs font-bold text-slate-400">NEXT SESSION</p>
                    <div className="px-2 py-0.5 bg-indigo-500 rounded text-[10px] items-center">URGENT</div>
                  </div>
                  <h4 className="text-lg font-black mb-1">Apr 24, 2024 • 10:30 AM</h4>
                  <p className="text-xs text-slate-400 mb-4">Clinical Pilates & Mobility Focus</p>
                  <button className="w-full bg-white text-slate-900 py-3 rounded-2xl font-bold flex items-center justify-center gap-2 hover:bg-slate-100 transition-all">
                    Prepare Session Notes
                  </button>
                </div>
              </div>
            </div>
          </motion.div>
        ) : (
          <div className="lg:col-span-8 flex items-center justify-center bg-slate-50 dark:bg-slate-900/50 rounded-3xl border-2 border-dashed border-slate-200 dark:border-slate-800">
            <div className="text-center">
              <div className="w-16 h-16 bg-slate-100 dark:bg-slate-800 rounded-full flex items-center justify-center mx-auto mb-4 text-slate-400">
                <Users size={32} />
              </div>
              <p className="text-slate-500 font-bold">Select a patient to view details</p>
            </div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
};
