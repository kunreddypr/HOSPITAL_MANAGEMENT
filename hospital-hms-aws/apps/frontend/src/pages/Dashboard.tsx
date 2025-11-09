import { useEffect, useState } from 'react';
import { apiGet } from '../api/client';
import type { Appointment } from '../types';

export const DashboardPage = () => {
  const [appointments, setAppointments] = useState<Appointment[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const loadAppointments = async () => {
      try {
        const data = await apiGet<Appointment[]>('/api/v1/appointments');
        setAppointments(data);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Unknown error loading appointments');
      } finally {
        setIsLoading(false);
      }
    };

    loadAppointments().catch(console.error);
  }, []);

  if (isLoading) {
    return <p>Loading appointments...</p>;
  }

  if (error) {
    return <p className="error">{error}</p>;
  }

  return (
    <section className="card">
      <h2>Upcoming Appointments</h2>
      {appointments.length === 0 ? (
        <p>No appointments scheduled.</p>
      ) : (
        <ul className="list">
          {appointments.map((appt) => (
            <li key={appt.id}>
              <strong>{new Date(appt.scheduledAt).toLocaleString()}</strong> with {appt.provider}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
};
