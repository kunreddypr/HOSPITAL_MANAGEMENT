import { useEffect, useState } from 'react';
import { getCurrentUser, signOut } from 'aws-amplify/auth';
import './config/amplify';
import { LoginPage } from './pages/Login';
import { DashboardPage } from './pages/Dashboard';
import { BookAppointmentPage } from './pages/BookAppointment';

type View = 'dashboard' | 'book';

function App() {
  const [view, setView] = useState<View>('dashboard');
  const [isAuthenticated, setIsAuthenticated] = useState<boolean>(false);
  const [userEmail, setUserEmail] = useState<string>('');

  useEffect(() => {
    getCurrentUser()
      .then((user) => {
        setIsAuthenticated(true);
        setUserEmail(user.signInDetails?.loginId ?? '');
      })
      .catch(() => {
        setIsAuthenticated(false);
      });
  }, []);

  if (!isAuthenticated) {
    return (
      <main>
        <header>
          <h1>Hospital Management Suite</h1>
        </header>
        <LoginPage />
      </main>
    );
  }

  const handleSignOut = async () => {
    await signOut();
    setIsAuthenticated(false);
    window.location.reload();
  };

  return (
    <main>
      <header>
        <div>
          <h1>Hospital Management Suite</h1>
          <small>Signed in as {userEmail}</small>
        </div>
        <nav>
          <button className={view === 'dashboard' ? 'active' : ''} onClick={() => setView('dashboard')}>
            Dashboard
          </button>
          <button className={view === 'book' ? 'active' : ''} onClick={() => setView('book')}>
            Book Appointment
          </button>
          <button onClick={handleSignOut}>Sign out</button>
        </nav>
      </header>
      {view === 'dashboard' ? <DashboardPage /> : <BookAppointmentPage />}
    </main>
  );
}

export default App;
