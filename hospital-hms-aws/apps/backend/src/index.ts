import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import prisma from './prisma';
import appointmentsRouter from './routes/appointments';
import patientsRouter from './routes/patients';
import uploadsRouter from './routes/uploads';

const app = express();
app.use(cors());
app.use(express.json());

app.get('/healthz', async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ status: 'ok' });
  } catch (err) {
    console.error('Health check failed', err);
    res.status(500).json({ status: 'error', message: 'Database connectivity failed' });
  }
});

app.use(appointmentsRouter);
app.use(patientsRouter);
app.use(uploadsRouter);

const port = Number(process.env.PORT ?? 8080);

app.listen(port, () => {
  console.log(`API listening on port ${port}`);
});
