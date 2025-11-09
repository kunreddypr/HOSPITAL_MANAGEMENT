import { useForm } from 'react-hook-form';
import { useState } from 'react';
import { apiPost } from '../api/client';
import type { Appointment } from '../types';

type AppointmentForm = {
  patientId: string;
  provider: string;
  scheduledAt: string;
  notes?: string;
};

export const BookAppointmentPage = () => {
  const { register, handleSubmit, reset } = useForm<AppointmentForm>();
  const [status, setStatus] = useState<string>('');

  const onSubmit = async (data: AppointmentForm) => {
    setStatus('Saving appointment...');
    try {
      const created = await apiPost<Appointment, AppointmentForm>('/api/v1/appointments', data);
      setStatus(`Appointment scheduled for ${new Date(created.scheduledAt).toLocaleString()}`);
      reset();
    } catch (err) {
      setStatus(err instanceof Error ? err.message : 'Error creating appointment');
    }
  };

  return (
    <section className="card">
      <h2>Book New Appointment</h2>
      <form onSubmit={handleSubmit(onSubmit)} className="form">
        <label>
          Patient ID
          <input {...register('patientId', { required: true })} placeholder="patient-123" />
        </label>
        <label>
          Provider
          <input {...register('provider', { required: true })} placeholder="Dr. Smith" />
        </label>
        <label>
          Scheduled Time
          <input type="datetime-local" {...register('scheduledAt', { required: true })} />
        </label>
        <label>
          Notes
          <textarea {...register('notes')} placeholder="Optional notes" />
        </label>
        <button type="submit" className="button">
          Submit
        </button>
      </form>
      {status && <p className="status">{status}</p>}
    </section>
  );
};
