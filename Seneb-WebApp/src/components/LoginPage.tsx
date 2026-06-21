import React, { useState } from 'react';
import { 
  Stethoscope, 
  Mail, 
  Lock, 
  ArrowRight, 
  Activity,
  ShieldCheck,
  Globe
} from 'lucide-react';
import { motion } from 'motion/react';

interface LoginPageProps {
  onLogin: () => void;
}

export const LoginPage: React.FC<LoginPageProps> = ({ onLogin }) => {
  const [email, setEmail] = useState('sarah.wilson@physioflow.com');
  const [password, setPassword] = useState('password');
  const [isLoading, setIsLoading] = useState(false);

  const handleLogin = (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);
    setTimeout(() => {
      onLogin();
      setIsLoading(false);
    }, 1500);
  };

  return (
    <div className="min-h-screen bg-white flex flex-col md:flex-row overflow-hidden font-sans">
      {/* Visual Side */}
      <div className="hidden md:flex md:w-1/2 bg-sky-600 relative overflow-hidden flex-col justify-between p-16 text-white">
        <div className="z-10">
          <div className="inline-flex items-center gap-2 bg-white/10 backdrop-blur-md px-4 py-2 rounded-lg mb-8 outline outline-1 outline-white/20">
            <Activity size={18} className="text-white" />
            <span className="text-sm font-bold tracking-tight">Seneb Cloud</span>
          </div>
          <h2 className="text-6xl font-black leading-tight mb-6 tracking-tighter">
            Efficiency through <br />
            structured care.
          </h2>
          <p className="text-lg text-sky-100 max-w-md font-medium leading-relaxed opacity-90">
            The modern Bento-styled workspace for clinical excellence and patient recovery management.
          </p>
        </div>

        <div className="z-10 bg-sky-800/40 backdrop-blur-xl border border-white/10 p-8 rounded-2xl flex gap-12 self-start ring-1 ring-white/20">
          <div>
            <p className="text-3xl font-black mb-1">124</p>
            <p className="text-[10px] uppercase font-bold tracking-widest text-sky-200">Active Patients</p>
          </div>
          <div className="w-px bg-white/10"></div>
          <div>
            <p className="text-3xl font-black mb-1">4.9</p>
            <p className="text-[10px] uppercase font-bold tracking-widest text-sky-200">Rating</p>
          </div>
          <div className="w-px bg-white/10"></div>
          <div>
            <p className="text-3xl font-black mb-1">82%</p>
            <p className="text-[10px] uppercase font-bold tracking-widest text-sky-200">Adherence</p>
          </div>
        </div>

        {/* Abstract shapes */}
        <div className="absolute top-[-10%] right-[-10%] w-[600px] h-[600px] bg-sky-500 rounded-full blur-[120px] opacity-30"></div>
        <div className="absolute bottom-[-10%] left-[-10%] w-[400px] h-[400px] bg-sky-700 rounded-full blur-[80px] opacity-40"></div>
      </div>

      {/* Form Side */}
      <div className="flex-1 flex items-center justify-center p-8 bg-slate-50 dark:bg-slate-950">
        <motion.div 
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="w-full max-w-md space-y-10"
        >
          <div className="text-center md:text-left">
            <div className="w-14 h-14 bg-sky-600 rounded-2xl flex items-center justify-center text-white mb-8 mx-auto md:mx-0 shadow-lg shadow-sky-600/20 font-extrabold text-3xl">
              S
            </div>
            <h1 className="text-3xl font-bold text-slate-900 dark:text-white mb-2 tracking-tight">Access Seneb</h1>
            <p className="text-slate-500 text-sm font-medium">Welcome back, Dr. Miller. Secure your session.</p>
          </div>

          <form onSubmit={handleLogin} className="space-y-6">
            <div className="space-y-2">
              <label className="text-[10px] font-bold text-slate-400 uppercase tracking-widest px-1">
                Clinical Email
              </label>
              <input 
                type="email" 
                required
                className="w-full bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 focus:border-sky-600 rounded-xl p-3.5 text-sm font-bold outline-none transition-all shadow-sm focus:ring-4 focus:ring-sky-600/5"
                placeholder="sarah.miller@physioflow.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
              />
            </div>

            <div className="space-y-2">
              <div className="flex justify-between items-center px-1">
                <label className="text-[10px] font-bold text-slate-400 uppercase tracking-widest">
                  Secure Password
                </label>
              </div>
              <input 
                type="password" 
                required
                className="w-full bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 focus:border-sky-600 rounded-xl p-3.5 text-sm font-bold outline-none transition-all shadow-sm focus:ring-4 focus:ring-sky-600/5"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </div>

            <div className="flex items-center gap-3 bg-white dark:bg-slate-900 p-4 rounded-xl border border-slate-200 dark:border-slate-800 shadow-sm">
               <ShieldCheck className="text-sky-500" size={18} />
               <p className="text-[11px] text-slate-500 font-bold leading-tight">Biometric and RSA-2048 encryption enabled for HIPAA compliance.</p>
            </div>

            <button 
              type="submit"
              disabled={isLoading}
              className="w-full bg-sky-600 text-white rounded-xl py-4 font-bold text-base flex items-center justify-center gap-3 shadow-md shadow-sky-600/20 hover:bg-sky-700 transition-all active:scale-[0.98] disabled:opacity-50"
            >
              {isLoading ? (
                <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin"></div>
              ) : (
                <>Sign into Seneb Workspace <ArrowRight size={20} /></>
              )}
            </button>
          </form>

          <footer className="text-center pt-8 border-t border-slate-200 dark:border-slate-900">
            <p className="text-[10px] font-bold text-slate-400 uppercase tracking-[0.2em]">Medical-Grade Infrastructure v4.0</p>
          </footer>
        </motion.div>
      </div>
    </div>
  );
};
