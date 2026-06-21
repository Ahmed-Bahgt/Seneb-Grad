import React, { useState } from 'react';
import { 
  Search, 
  Filter, 
  Info, 
  CheckCircle2, 
  PlayCircle,
  Dumbbell,
  ShieldCheck,
  Zap,
  LayoutGrid,
  List as ListIcon,
  Plus
} from 'lucide-react';
import { mockExercises, mockPatients } from '../data/mockData';
import { Exercise } from '../types';
import { cn } from '../lib/utils';
import { motion, AnimatePresence } from 'motion/react';

export const ExercisesPage: React.FC = () => {
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('All');
  const [selectedExercise, setSelectedExercise] = useState<Exercise | null>(null);
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid');

  const categories = ['All', 'Lower Body', 'Core', 'Shoulder', 'Upper Body', 'Flexibility'];

  const filteredExercises = mockExercises.filter(ex => {
    const matchesSearch = ex.name.toLowerCase().includes(searchTerm.toLowerCase()) || 
                         ex.description.toLowerCase().includes(searchTerm.toLowerCase());
    const matchesCategory = selectedCategory === 'All' || ex.category === selectedCategory;
    return matchesSearch && matchesCategory;
  });

  return (
    <div className="space-y-8">
      {/* Header Section */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-6">
        <div>
          <h1 className="text-2xl font-black text-slate-900 dark:text-white mb-2 flex items-center gap-3">
            <Dumbbell className="text-indigo-600" /> Clinical Exercise Catalog
          </h1>
          <p className="text-slate-500 font-medium font-mono text-xs uppercase tracking-wider">
            {mockExercises.length} Verified protocols available
          </p>
        </div>
        <div className="flex items-center gap-3">
          <div className="flex bg-slate-100 dark:bg-slate-800 p-1 rounded-xl">
            <button 
              onClick={() => setViewMode('grid')}
              className={cn("p-2 rounded-lg transition-all", viewMode === 'grid' ? "bg-white dark:bg-slate-700 shadow-sm text-indigo-600" : "text-slate-400")}
            >
              <LayoutGrid size={18} />
            </button>
            <button 
              onClick={() => setViewMode('list')}
              className={cn("p-2 rounded-lg transition-all", viewMode === 'list' ? "bg-white dark:bg-slate-700 shadow-sm text-indigo-600" : "text-slate-400")}
            >
              <ListIcon size={18} />
            </button>
          </div>
          <button className="flex items-center gap-2 px-6 py-3 bg-indigo-600 text-white font-bold rounded-2xl text-sm transition-all shadow-lg shadow-indigo-600/20 hover:bg-indigo-700">
            <Plus size={18} /> Create Exercise
          </button>
        </div>
      </div>

      {/* Filters & Search */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 bg-white dark:bg-slate-900 p-6 rounded-3xl border border-slate-200 dark:border-slate-800 shadow-sm">
        <div className="lg:col-span-4 relative group">
          <Search className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400 group-focus-within:text-indigo-600 transition-colors" size={18} />
          <input 
            type="text" 
            placeholder="Search mechanics, anatomy, or names..."
            className="w-full bg-slate-50 dark:bg-slate-800 border-none rounded-2xl py-3.5 pl-12 pr-4 text-sm font-medium focus:ring-2 focus:ring-indigo-600/10 outline-none"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
        </div>
        <div className="lg:col-span-8 flex items-center gap-2 overflow-x-auto no-scrollbar pb-1">
          {categories.map(cat => (
            <button
              key={cat}
              onClick={() => setSelectedCategory(cat)}
              className={cn(
                "px-5 py-2.5 rounded-xl text-sm font-bold whitespace-nowrap transition-all border-2",
                selectedCategory === cat 
                  ? "bg-indigo-600 text-white border-indigo-600 shadow-md shadow-indigo-600/20" 
                  : "bg-white dark:bg-slate-800 text-slate-500 border-slate-50 dark:border-slate-800 hover:border-slate-200"
              )}
            >
              {cat}
            </button>
          ))}
        </div>
      </div>

      {/* Exercise Gallery */}
      <div className={cn(
        "grid gap-6",
        viewMode === 'grid' ? "grid-cols-1 md:grid-cols-2 lg:grid-cols-4" : "grid-cols-1"
      )}>
        {filteredExercises.map((exercise) => (
          <motion.div
            layoutId={exercise.id}
            key={exercise.id}
            whileHover={{ y: -6 }}
            className="bg-white dark:bg-slate-900 rounded-3xl border border-slate-200 dark:border-slate-800 overflow-hidden shadow-sm group cursor-pointer"
            onClick={() => setSelectedExercise(exercise)}
          >
            <div className="relative h-48 overflow-hidden">
              <img 
                src={exercise.imageUrl} 
                className="w-full h-full object-cover transition-transform duration-700 group-hover:scale-110" 
                alt={exercise.name}
              />
              <div className="absolute top-4 left-4 flex gap-2">
                <span className={cn(
                  "px-3 py-1 rounded-full text-[10px] font-black uppercase tracking-wider shadow-sm",
                  exercise.difficulty === 'Beginner' ? "bg-emerald-500 text-white" : 
                  exercise.difficulty === 'Intermediate' ? "bg-amber-500 text-white" : "bg-red-500 text-white"
                )}>
                  {exercise.difficulty}
                </span>
              </div>
              <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
                <div className="w-12 h-12 rounded-full bg-white/20 backdrop-blur-md flex items-center justify-center text-white">
                  <PlayCircle size={32} />
                </div>
              </div>
            </div>
            <div className="p-6">
              <div className="flex items-center justify-between mb-2">
                <span className="text-[10px] font-black text-indigo-500 uppercase tracking-widest">{exercise.category}</span>
                <ShieldCheck size={16} className="text-slate-300" />
              </div>
              <h3 className="text-lg font-black text-slate-900 dark:text-white mb-2 leading-tight">{exercise.name}</h3>
              <p className="text-xs text-slate-500 font-medium line-clamp-2 leading-relaxed mb-4">
                {exercise.description}
              </p>
              <div className="flex items-center justify-between border-t border-slate-50 dark:border-slate-800 pt-4 mt-auto">
                <div className="flex items-center gap-1.5 text-xs font-black text-slate-400 uppercase">
                  <Zap size={14} className="text-amber-500" /> Clinical Pick
                </div>
                <div className="flex -space-x-2">
                  <div className="w-6 h-6 rounded-full border-2 border-white dark:border-slate-900 bg-slate-200 overflow-hidden">
                    <img src="https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=50&h=50&fit=crop" alt="" />
                  </div>
                  <div className="w-6 h-6 rounded-full border-2 border-white dark:border-slate-900 bg-slate-200 overflow-hidden">
                    <img src="https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?w=50&h=50&fit=crop" alt="" />
                  </div>
                  <div className="w-6 h-6 rounded-full border-2 border-white dark:border-slate-900 bg-indigo-100 flex items-center justify-center text-[8px] font-black text-indigo-600">
                    +12
                  </div>
                </div>
              </div>
            </div>
          </motion.div>
        ))}
      </div>

      {/* Detail & Assignment Modal */}
      <AnimatePresence>
        {selectedExercise && (
          <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
            <motion.div 
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setSelectedExercise(null)}
              className="absolute inset-0 bg-slate-900/60 backdrop-blur-md"
            ></motion.div>
            
            <motion.div 
              layoutId={selectedExercise.id}
              className="relative w-full max-w-4xl bg-white dark:bg-slate-900 rounded-[3rem] overflow-hidden shadow-2xl overflow-y-auto max-h-[90vh]"
            >
              <div className="grid grid-cols-1 md:grid-cols-2 h-full">
                <div className="relative bg-slate-100 h-64 md:h-full">
                  <img 
                    src={selectedExercise.imageUrl} 
                    className="w-full h-full object-cover" 
                    alt="" 
                  />
                  <div className="absolute top-8 left-8">
                    <button 
                      onClick={() => setSelectedExercise(null)}
                      className="w-12 h-12 bg-white/20 backdrop-blur-md border border-white/30 rounded-full flex items-center justify-center text-white"
                    >
                      <Plus className="rotate-45" size={24} />
                    </button>
                  </div>
                </div>

                <div className="p-12 space-y-8">
                  <div>
                    <span className="text-xs font-black text-indigo-600 uppercase tracking-widest bg-indigo-50 dark:bg-indigo-500/10 px-3 py-1 rounded-full">{selectedExercise.category}</span>
                    <h2 className="text-4xl font-black text-slate-900 dark:text-white mt-4">{selectedExercise.name}</h2>
                  </div>

                  <div className="space-y-4">
                    <h3 className="text-xs font-black text-slate-400 uppercase tracking-widest flex items-center gap-2">
                       <Info size={14} /> Description
                    </h3>
                    <p className="text-slate-600 dark:text-slate-400 leading-relaxed font-medium">
                      {selectedExercise.description}
                    </p>
                  </div>

                  <div className="p-6 bg-slate-50 dark:bg-slate-800 rounded-3xl border border-slate-100 dark:border-slate-700 space-y-6">
                    <h3 className="text-xs font-black text-slate-400 uppercase tracking-widest">Assign to Patient</h3>
                    <div className="space-y-4">
                      <div>
                        <label className="block text-[10px] font-black text-slate-400 uppercase mb-2">Select Patient</label>
                        <select className="w-full bg-white dark:bg-slate-700 border-2 border-slate-100 dark:border-slate-600 rounded-2xl p-4 text-sm font-bold outline-none ring-indigo-500/20 focus:ring-4">
                          {mockPatients.map(p => (
                            <option key={p.id} value={p.id}>{p.name}</option>
                          ))}
                        </select>
                      </div>
                      <div className="grid grid-cols-2 gap-4">
                        <div>
                          <label className="block text-[10px] font-black text-slate-400 uppercase mb-2">Sets</label>
                          <input type="number" defaultValue="3" className="w-full bg-white dark:bg-slate-700 border-2 border-slate-100 dark:border-slate-600 rounded-2xl p-4 text-sm font-bold outline-none" />
                        </div>
                        <div>
                          <label className="block text-[10px] font-black text-slate-400 uppercase mb-2">Reps</label>
                          <input type="number" defaultValue="12" className="w-full bg-white dark:bg-slate-700 border-2 border-slate-100 dark:border-slate-600 rounded-2xl p-4 text-sm font-bold outline-none" />
                        </div>
                      </div>
                    </div>
                  </div>

                  <button className="w-full bg-indigo-600 text-white py-5 rounded-[2rem] font-black text-lg flex items-center justify-center gap-3 shadow-xl shadow-indigo-600/20 hover:bg-indigo-700 transition-all hover:translate-y-[-2px]">
                    <CheckCircle2 size={24} /> Assign Protocol
                  </button>
                </div>
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
};
