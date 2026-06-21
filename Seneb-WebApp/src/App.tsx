import { useState, useEffect } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { DashboardLayout } from './components/layout/DashboardLayout';
import { LoginPage } from './components/LoginPage';
import { DashboardPage } from './components/DashboardPage';
import { PatientsPage } from './components/PatientsPage';
import { CalendarPage } from './components/CalendarPage';
import { ExercisesPage } from './components/ExercisesPage';
import { MessagingPage } from './components/MessagingPage';
import { AIChat } from './components/AIChat';

export default function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);

  // Check for stored auth (demo purposes)
  useEffect(() => {
    const auth = localStorage.getItem('physio_auth');
    if (auth === 'true') setIsAuthenticated(true);
  }, []);

  const handleLogin = () => {
    localStorage.setItem('physio_auth', 'true');
    setIsAuthenticated(true);
  };

  const handleLogout = () => {
    localStorage.removeItem('physio_auth');
    setIsAuthenticated(false);
  };

  if (!isAuthenticated) {
    return <LoginPage onLogin={handleLogin} />;
  }

  return (
    <BrowserRouter>
      <DashboardLayout>
        <Routes>
          <Route path="/" element={<DashboardPage />} />
          <Route path="/patients" element={<PatientsPage />} />
          <Route path="/schedule" element={<CalendarPage />} />
          <Route path="/exercises" element={<ExercisesPage />} />
          <Route path="/messages" element={<MessagingPage />} />
          <Route path="/ai-assistant" element={
            <div className="flex flex-col items-center justify-center h-[calc(100vh-12rem)] space-y-6">
              <div className="w-24 h-24 bg-sky-600 rounded-[2rem] flex items-center justify-center text-white shadow-2xl shadow-sky-600/30 font-black text-4xl">
                S
              </div>
              <div className="text-center">
                <h2 className="text-3xl font-black text-slate-900 dark:text-white mb-2">Omnipresent Seneb</h2>
                <p className="text-slate-500 font-medium px-4">Click the sparkle icon in the bottom right corner to interact with your Seneb Clinical Assistant anywhere.</p>
              </div>
            </div>
          } />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
        <AIChat />
      </DashboardLayout>
    </BrowserRouter>
  );
}
