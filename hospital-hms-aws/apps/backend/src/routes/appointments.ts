import { Router } from 'express';
import prisma from '../prisma';
import { authMiddleware } from '../middleware/auth';
import { writeAuditLog } from '../clients/aws';

const router = Router();

router.get('/api/v1/appointments', authMiddleware, async (_req, res) => {
  const appointments = await prisma.appointment.findMany({
    select: {
      id: true,
      patientId: true,
      provider: true,
      scheduledAt: true,
      notes: true
    },
    orderBy: { scheduledAt: 'asc' }
  });

  res.json(appointments);
});

router.post('/api/v1/appointments', authMiddleware, async (req, res) => {
  const { patientId, provider, scheduledAt, notes } = req.body as {
    patientId?: string;
    provider?: string;
    scheduledAt?: string;
    notes?: string;
  };

  if (!patientId || !provider || !scheduledAt) {
    return res.status(400).json({ message: 'patientId, provider and scheduledAt are required' });
  }

  const appointment = await prisma.appointment.create({
    data: {
      patientId,
      provider,
      scheduledAt: new Date(scheduledAt),
      notes
    },
    select: {
      id: true,
      patientId: true,
      provider: true,
      scheduledAt: true,
      notes: true
    }
  });

  const tableName = process.env.DDB_TABLE;
  if (tableName) {
    await writeAuditLog(tableName, {
      action: 'CREATE_APPOINTMENT',
      appointmentId: appointment.id,
      userSub: req.user?.sub ?? 'unknown'
    }).catch((err) => {
      console.error('Failed to write audit log', err);
    });
  }

  res.status(201).json(appointment);
});

export default router;
