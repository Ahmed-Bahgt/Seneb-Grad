import React, { useState } from 'react';
import { 
  Send, 
  Paperclip, 
  Smile, 
  Search, 
  MoreVertical,
  Phone,
  Video,
  Info,
  CheckCheck
} from 'lucide-react';
import { mockMessages, mockPatients, mockUsers } from '../data/mockData';
import { cn } from '../lib/utils';
import { format } from 'date-fns';
import { motion, AnimatePresence } from 'motion/react';

export const MessagingPage: React.FC = () => {
  const [selectedChat, setSelectedChat] = useState(mockPatients[0].id);
  const [message, setMessage] = useState('');
  const currentUser = mockUsers[0];
  const activePatient = mockPatients.find(p => p.id === selectedChat);

  const [localMessages, setLocalMessages] = useState(mockMessages);

  const sendMessage = (e?: React.FormEvent) => {
    e?.preventDefault();
    if (!message.trim()) return;

    const newMessage = {
      id: Date.now().toString(),
      senderId: currentUser.id,
      receiverId: selectedChat,
      content: message,
      timestamp: new Date().toISOString()
    };

    setLocalMessages([...localMessages, newMessage]);
    setMessage('');
  };

  return (
    <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 h-[calc(100vh-10rem)]">
      {/* Chats Sidebar */}
      <div className="lg:col-span-4 bg-white dark:bg-slate-900 rounded-3xl border border-slate-200 dark:border-slate-800 flex flex-col overflow-hidden">
        <div className="p-8 border-b border-slate-100 dark:border-slate-800">
          <h2 className="text-2xl font-black text-slate-900 dark:text-white mb-6">Messages</h2>
          <div className="relative group">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400 group-focus-within:text-indigo-600 transition-colors" size={16} />
            <input 
              type="text" 
              placeholder="Search conversations..."
              className="w-full bg-slate-100 dark:bg-slate-800 border-none rounded-xl py-2.5 pl-10 pr-4 text-sm font-medium focus:ring-2 focus:ring-indigo-600/10 outline-none"
            />
          </div>
        </div>

        <div className="flex-1 overflow-y-auto p-4 space-y-2">
          {mockPatients.map((patient) => {
            const lastMsg = localMessages.filter(m => (m.senderId === patient.id || m.receiverId === patient.id)).at(-1);
            return (
              <button
                key={patient.id}
                onClick={() => setSelectedChat(patient.id)}
                className={cn(
                  "w-full text-left p-4 rounded-2xl flex items-center gap-4 transition-all group",
                  selectedChat === patient.id 
                    ? "bg-indigo-50 dark:bg-indigo-500/10 border-indigo-100" 
                    : "hover:bg-slate-50 dark:hover:bg-slate-800/50"
                )}
              >
                <div className="relative">
                  <div className="w-12 h-12 rounded-2xl bg-indigo-100 dark:bg-indigo-900/30 flex items-center justify-center font-bold text-indigo-600">
                    {patient.name.charAt(0)}
                  </div>
                  {patient.status === 'active' && (
                    <span className="absolute -bottom-1 -right-1 w-4 h-4 bg-emerald-500 border-4 border-white dark:border-slate-900 rounded-full"></span>
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between mb-1">
                    <p className="font-bold text-sm text-slate-900 dark:text-white truncate">{patient.name}</p>
                    <span className="text-[10px] text-slate-400 font-bold">
                      {lastMsg ? format(new Date(lastMsg.timestamp), 'HH:mm') : 'None'}
                    </span>
                  </div>
                  <p className="text-xs text-slate-500 font-medium truncate">
                    {lastMsg ? lastMsg.content : 'No messages yet'}
                  </p>
                </div>
              </button>
            );
          })}
        </div>
      </div>

      {/* Chat Window */}
      <div className="lg:col-span-8 bg-white dark:bg-slate-900 rounded-3xl border border-slate-200 dark:border-slate-800 flex flex-col overflow-hidden shadow-sm">
        {/* Chat Header */}
        <div className="p-6 border-b border-slate-100 dark:border-slate-800 flex items-center justify-between bg-white/50 dark:bg-slate-900/50 backdrop-blur-sm z-10">
          <div className="flex items-center gap-4">
            <div className="w-12 h-12 rounded-2xl bg-indigo-600 flex items-center justify-center text-white font-black text-xl">
              {activePatient?.name.charAt(0)}
            </div>
            <div>
              <h3 className="text-lg font-black text-slate-900 dark:text-white leading-tight">{activePatient?.name}</h3>
              <p className="text-xs text-emerald-500 font-bold flex items-center gap-1">
                <span className="w-1.5 h-1.5 bg-emerald-500 rounded-full animate-pulse"></span> Online
              </p>
            </div>
          </div>
          <div className="flex gap-2">
            <button className="p-3 text-slate-400 hover:text-indigo-600 hover:bg-slate-50 dark:hover:bg-slate-800 rounded-xl transition-all">
              <Phone size={20} />
            </button>
            <button className="p-3 text-slate-400 hover:text-indigo-600 hover:bg-slate-50 dark:hover:bg-slate-800 rounded-xl transition-all">
              <Video size={20} />
            </button>
            <button className="p-3 text-slate-400 hover:text-indigo-600 hover:bg-slate-50 dark:hover:bg-slate-800 rounded-xl transition-all">
              <Info size={20} />
            </button>
          </div>
        </div>

        {/* Message Area */}
        <div className="flex-1 overflow-y-auto p-8 space-y-6">
          {localMessages.filter(m => m.senderId === selectedChat || m.receiverId === selectedChat).map((msg) => {
            const isMe = msg.senderId === currentUser.id;
            return (
              <motion.div 
                initial={{ opacity: 0, y: 10, scale: 0.95 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                key={msg.id} 
                className={cn(
                  "flex",
                  isMe ? "justify-end" : "justify-start"
                )}
              >
                <div className={cn(
                  "max-w-[70%] p-5 rounded-3xl text-sm font-medium relative group",
                  isMe 
                    ? "bg-indigo-600 text-white rounded-br-none shadow-xl shadow-indigo-600/20" 
                    : "bg-slate-100 dark:bg-slate-800 text-slate-900 dark:text-slate-100 rounded-bl-none"
                )}>
                  {msg.content}
                  <div className={cn(
                    "flex items-center gap-2 mt-2 opacity-0 group-hover:opacity-100 transition-opacity",
                    isMe ? "justify-end" : "justify-start"
                  )}>
                    <span className="text-[10px] font-bold text-current/60">
                      {format(new Date(msg.timestamp), 'HH:mm')}
                    </span>
                    {isMe && <CheckCheck size={12} className="text-indigo-200" />}
                  </div>
                </div>
              </motion.div>
            );
          })}
        </div>

        {/* Input Area */}
        <div className="p-6 border-t border-slate-100 dark:border-slate-800 bg-slate-50/50 dark:bg-slate-800/30">
          <form onSubmit={sendMessage} className="flex items-center gap-3">
            <button type="button" className="p-3 text-slate-400 hover:text-indigo-600 hover:bg-white dark:hover:bg-slate-700 rounded-2xl transition-all shadow-sm">
              <Paperclip size={20} />
            </button>
            <div className="flex-1 relative">
              <input 
                type="text" 
                placeholder="Write your clinical advice..."
                className="w-full bg-white dark:bg-slate-800 border-2 border-transparent focus:border-indigo-600/20 rounded-2xl py-4 px-6 text-sm font-medium outline-none shadow-sm transition-all"
                value={message}
                onChange={(e) => setMessage(e.target.value)}
              />
              <button type="button" className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-400 hover:text-amber-500 transition-colors">
                <Smile size={20} />
              </button>
            </div>
            <button 
              type="submit"
              className="p-4 bg-indigo-600 text-white rounded-2xl hover:bg-indigo-700 transition-all shadow-xl shadow-indigo-600/20 hover:scale-105 active:scale-95"
            >
              <Send size={24} />
            </button>
          </form>
        </div>
      </div>
    </div>
  );
};
