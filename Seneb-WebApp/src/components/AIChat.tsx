import React, { useState, useEffect, useRef } from 'react';
import { 
  Sparkles, 
  Send, 
  X, 
  Minus, 
  ChevronUp, 
  MessageSquare, 
  Bot, 
  User,
  Zap,
  Loader2
} from 'lucide-react';
import { GoogleGenAI } from "@google/genai";
import { cn } from '../lib/utils';
import { motion, AnimatePresence } from 'motion/react';

let genAIInstance: GoogleGenAI | null = null;
const getGenAI = () => {
  if (!genAIInstance) {
    let apiKey = "";
    try {
      apiKey = process.env.GEMINI_API_KEY || "";
    } catch (e) {
      console.warn("process.env.GEMINI_API_KEY is not accessible safely");
    }
    
    if (!apiKey) {
      return null;
    }
    genAIInstance = new GoogleGenAI({ apiKey });
  }
  return genAIInstance;
};

interface Message {
  role: 'user' | 'assistant';
  content: string;
}

export const AIChat: React.FC = () => {
  const [isOpen, setIsOpen] = useState(false);
  const [isMinimized, setIsMinimized] = useState(false);
  const [input, setInput] = useState('');
  const [messages, setMessages] = useState<Message[]>([
    { role: 'assistant', content: 'Hello! I am your AI Physiotherapy Assistant. I can help you with anatomy questions, treatment protocols, or exercise variations. How can I assist you today?' }
  ]);
  const [isLoading, setIsLoading] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!input.trim() || isLoading) return;

    const userMsg = input;
    setInput('');
    setMessages(prev => [...prev, { role: 'user', content: userMsg }]);
    setIsLoading(true);

    try {
      const ai = getGenAI();
      if (!ai) {
        setMessages(prev => [...prev, { role: 'assistant', content: "AI settings are not configured. Please add your GEMINI_API_KEY to continue." }]);
        setIsLoading(false);
        return;
      }
      const modelName = "gemini-3-flash-preview";
      
      const response = await ai.models.generateContent({
        model: modelName,
        contents: userMsg,
        config: {
          systemInstruction: "You are Seneb, a professional Physiotherapy Assistant. Provide accurate anatomical info, evidence-based treatment suggestions, and exercise variations. Keep responses concise and clinical but helpful. Redirect non-medical queries back to physiotherapy.",
        }
      });

      const responseText = response.text || "I'm sorry, I couldn't generate a response.";
      setMessages(prev => [...prev, { role: 'assistant', content: responseText }]);
    } catch (error) {
      console.error("AI Error:", error);
      setMessages(prev => [...prev, { role: 'assistant', content: "Sorry, I encountered an error connecting to the AI brain. Please check your API configuration." }]);
    } finally {
      setIsLoading(false);
    }
  };

  if (!isOpen) {
    return (
      <button 
        onClick={() => setIsOpen(true)}
        className="fixed bottom-8 right-8 w-16 h-16 bg-sky-600 text-white rounded-2xl shadow-[0_20px_40px_rgba(2,132,199,0.3)] flex items-center justify-center hover:scale-110 active:scale-95 transition-all z-[100] group overflow-hidden"
      >
        <div className="absolute inset-0 bg-white opacity-0 group-hover:opacity-20 transition-opacity"></div>
        <Sparkles size={28} />
      </button>
    );
  }

  return (
    <div className={cn(
      "fixed bottom-8 right-8 z-[100] flex flex-col transition-all duration-300",
      isMinimized ? "h-20 w-80" : "h-[600px] w-[400px]"
    )}>
      <div className="bg-white dark:bg-slate-900 h-full rounded-3xl shadow-[0_30px_60px_rgba(0,0,0,0.15)] overflow-hidden flex flex-col border border-slate-200 dark:border-slate-800">
        {/* Header */}
        <div className="p-5 bg-sky-900 text-white flex items-center justify-between cursor-pointer" onClick={() => setIsMinimized(!isMinimized)}>
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-sky-800 rounded-lg flex items-center justify-center shadow-inner">
              <Bot size={22} className="text-sky-400" />
            </div>
            <div>
              <h3 className="font-bold text-sm text-white">Seneb Clinical Assistant</h3>
              <p className="text-[10px] uppercase font-black tracking-widest text-sky-400">Powered by Gemini</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <button 
              onClick={(e) => { e.stopPropagation(); setIsMinimized(!isMinimized); }}
              className="p-1.5 hover:bg-white/10 rounded-lg transition-colors"
            >
              {isMinimized ? <ChevronUp size={18} /> : <Minus size={18} />}
            </button>
            <button 
              onClick={(e) => { e.stopPropagation(); setIsOpen(false); }}
              className="p-1.5 hover:bg-white/10 rounded-lg transition-colors"
            >
              <X size={18} />
            </button>
          </div>
        </div>

        {!isMinimized && (
          <>
            {/* Messages Area */}
            <div ref={scrollRef} className="flex-1 overflow-y-auto p-6 space-y-6 scrollbar-hide bg-slate-50/50 dark:bg-slate-900">
              {messages.map((msg, idx) => (
                <div key={idx} className={cn(
                  "flex items-start gap-4",
                  msg.role === 'user' ? "flex-row-reverse" : ""
                )}>
                  <div className={cn(
                    "w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0",
                    msg.role === 'assistant' ? "bg-sky-100 dark:bg-sky-900/30 text-sky-600" : "bg-slate-100 dark:bg-slate-800 text-slate-500"
                  )}>
                    {msg.role === 'assistant' ? <Bot size={18} /> : <User size={18} />}
                  </div>
                  <div className={cn(
                    "p-4 rounded-2xl text-xs font-medium shadow-sm leading-relaxed",
                    msg.role === 'assistant' 
                      ? "bg-white dark:bg-slate-800 text-slate-800 dark:text-slate-100 rounded-tl-none border border-slate-100 dark:border-slate-700" 
                      : "bg-sky-600 text-white rounded-tr-none"
                  )}>
                    {msg.content}
                  </div>
                </div>
              ))}
              {isLoading && (
                <div className="flex items-start gap-4 animate-pulse">
                  <div className="w-8 h-8 rounded-lg bg-sky-50 dark:bg-sky-900/10 flex items-center justify-center">
                    <Loader2 size={18} className="text-sky-600 animate-spin" />
                  </div>
                  <div className="p-4 rounded-2xl text-xs bg-white dark:bg-slate-800 rounded-tl-none border border-slate-100 dark:border-slate-700 w-20">
                    <div className="flex gap-1">
                      <div className="w-1.5 h-1.5 bg-slate-200 rounded-full animate-bounce"></div>
                      <div className="w-1.5 h-1.5 bg-slate-200 rounded-full animate-bounce delay-75"></div>
                      <div className="w-1.5 h-1.5 bg-slate-200 rounded-full animate-bounce delay-150"></div>
                    </div>
                  </div>
                </div>
              )}
            </div>

            {/* Input Area */}
            <div className="p-5 bg-white dark:bg-slate-900 border-t border-slate-100 dark:border-slate-800">
              <form onSubmit={handleSubmit} className="flex gap-3">
                <input 
                  type="text" 
                  autoFocus
                  placeholder="Ask anything..."
                  className="flex-1 bg-slate-100 dark:bg-slate-800 border-none rounded-xl p-3 text-xs font-bold outline-none ring-sky-500/10 focus:ring-4 transition-all"
                  value={input}
                  onChange={(e) => setInput(e.target.value)}
                  disabled={isLoading}
                />
                <button 
                  disabled={isLoading}
                  className="w-10 h-10 bg-sky-600 text-white rounded-xl flex items-center justify-center hover:bg-sky-700 shadow-lg shadow-sky-600/30 transition-all disabled:opacity-50"
                >
                  <Send size={18} />
                </button>
              </form>
            </div>
          </>
        )}
      </div>
    </div>
  );
};
