export interface Appointment {
  id: string;
  patientId: string;
  provider: string;
  scheduledAt: string;
  notes?: string;
}

export interface Patient {
  id: string;
  firstName: string;
  lastName: string;
  dateOfBirth: string;
}
