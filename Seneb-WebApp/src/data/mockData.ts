import { User, Patient, Appointment, Exercise, Message } from '../types';

export const mockUsers: User[] = [
  {
    id: 't1',
    name: 'Dr. Sarah Wilson',
    email: 'sarah.wilson@physiotrack.com',
    role: 'therapist',
    avatar: 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=100&h=100&fit=crop'
  },
  {
    id: 't2',
    name: 'Dr. James Chen',
    email: 'james.chen@physiotrack.com',
    role: 'therapist',
    avatar: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=100&h=100&fit=crop'
  }
];

export const mockPatients: Patient[] = [
  {
    id: 'p1',
    name: 'Emma Thompson',
    age: 28,
    email: 'emma.t@example.com',
    phone: '+1 (555) 123-4567',
    injuryType: 'ACL Tear',
    injuryDescription: 'Post-operative recovery from ACL reconstruction surgery.',
    treatmentPlan: 'Strengthening quadriceps and hamstrings, improving range of motion.',
    status: 'active',
    assignedTherapistId: 't1',
    adherenceRate: 85,
    satisfaction: 4.8,
    lastVisit: '2024-03-20',
    joinedAt: '2024-01-15'
  },
  {
    id: 'p2',
    name: 'Michael Ross',
    age: 42,
    email: 'm.ross@example.com',
    phone: '+1 (555) 987-6543',
    injuryType: 'Lower Back Pain',
    injuryDescription: 'Chronic lower back pain possibly due to sedentary lifestyle.',
    treatmentPlan: 'Core stabilization exercises, ergonomic education, and light stretching.',
    status: 'active',
    assignedTherapistId: 't1',
    adherenceRate: 60,
    satisfaction: 4.2,
    lastVisit: '2024-03-22',
    joinedAt: '2024-02-10'
  },
  {
    id: 'p3',
    name: 'Sophia Williams',
    age: 35,
    email: 'sophia@example.com',
    phone: '+1 (555) 456-7890',
    injuryType: 'Shoulder Impingement',
    injuryDescription: 'Pain in reaching overhead, limited mobility in the right shoulder.',
    treatmentPlan: 'Rotator cuff strengthening and scapular stabilization.',
    status: 'inactive',
    assignedTherapistId: 't2',
    adherenceRate: 95,
    satisfaction: 5.0,
    lastVisit: '2024-03-05',
    joinedAt: '2023-11-20'
  }
];

export const mockAppointments: Appointment[] = [
  {
    id: 'a1',
    patientId: 'p1',
    therapistId: 't1',
    date: '2024-04-20T10:00:00Z',
    type: 'therapy',
    notes: 'Focus on knee extension exercises.',
    status: 'scheduled'
  },
  {
    id: 'a2',
    patientId: 'p2',
    therapistId: 't1',
    date: '2024-04-20T11:30:00Z',
    type: 'assessment',
    notes: 'Bio-mechanical assessment of gait.',
    status: 'scheduled'
  },
  {
    id: 'a3',
    patientId: 'p1',
    therapistId: 't1',
    date: '2024-04-22T14:00:00Z',
    type: 'follow-up',
    status: 'scheduled'
  }
];

export const mockExercises: Exercise[] = [
  {
    id: 'e1',
    name: 'Wall Squats',
    description: 'Stand with your back against a wall. Slide down until your thighs are parallel to the floor.',
    difficulty: 'Beginner',
    category: 'Lower Body',
    imageUrl: 'https://images.unsplash.com/photo-1574680096145-d05b474e2155?w=400&h=300&fit=crop'
  },
  {
    id: 'e2',
    name: 'Bird Dog',
    description: 'From all fours, reach one arm forward and the opposite leg back.',
    difficulty: 'Intermediate',
    category: 'Core',
    imageUrl: 'https://images.unsplash.com/photo-1518611012118-29a8d63a8368?w=400&h=300&fit=crop'
  },
  {
    id: 'e3',
    name: 'Plank',
    description: 'Hold a push-up position but rest on your forearms.',
    difficulty: 'Intermediate',
    category: 'Core',
    imageUrl: 'https://images.unsplash.com/photo-1566241477600-ac026ad43874?w=400&h=300&fit=crop'
  },
  {
    id: 'e4',
    name: 'Scapular Squeezes',
    description: 'Squeeze your shoulder blades together as if holding a pencil between them.',
    difficulty: 'Beginner',
    category: 'Shoulder',
    imageUrl: 'https://images.unsplash.com/photo-1594381898411-846e7d193883?w=400&h=300&fit=crop'
  }
];

export const mockMessages: Message[] = [
  {
    id: 'm1',
    senderId: 'p1',
    receiverId: 't1',
    content: 'Hi Dr. Sarah, I am feeling a bit of stiffness in my knee today after the squats.',
    timestamp: '2024-03-24T09:00:00Z'
  },
  {
    id: 'm2',
    senderId: 't1',
    receiverId: 'p1',
    content: 'That is normal, Emma. Try icing it for 15 minutes and doing some light stretches.',
    timestamp: '2024-03-24T09:15:00Z'
  }
];
