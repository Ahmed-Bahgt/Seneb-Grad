export type UserRole = 'admin' | 'therapist';

export interface User {
  id: string;
  name: string;
  email: string;
  role: UserRole;
  avatar?: string;
}

export interface Patient {
  id: string;
  name: string;
  age: number;
  email: string;
  phone: string;
  injuryType: string;
  injuryDescription: string;
  treatmentPlan: string;
  status: 'active' | 'inactive';
  assignedTherapistId: string;
  adherenceRate: number; // percentage
  satisfaction: number; // 1-5
  lastVisit: string;
  joinedAt: string;
}

export interface Appointment {
  id: string;
  patientId: string;
  therapistId: string;
  date: string; // ISO format
  type: 'initial' | 'follow-up' | 'assessment' | 'therapy';
  notes?: string;
  status: 'scheduled' | 'completed' | 'cancelled';
}

export interface Exercise {
  id: string;
  name: string;
  description: string;
  difficulty: 'Beginner' | 'Intermediate' | 'Advanced';
  category: string;
  imageUrl: string;
  sets?: number;
  reps?: number;
  videoUrl?: string;
}

export interface PatientExercise {
  id: string;
  patientId: string;
  exerciseId: string;
  assignedAt: string;
  frequency: string; // e.g., "3 times a week"
  notes: string;
  completed: boolean;
}

export interface Message {
  id: string;
  senderId: string;
  receiverId: string;
  content: string;
  timestamp: string;
  isAi?: boolean;
}
