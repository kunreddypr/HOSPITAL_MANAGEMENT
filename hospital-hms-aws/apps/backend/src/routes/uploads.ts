import { Router } from 'express';
import { authMiddleware } from '../middleware/auth';
import { createPresignedUploadUrl } from '../clients/aws';

const router = Router();

router.put('/api/v1/uploads/s3-presign', authMiddleware, async (req, res) => {
  const { fileName, contentType } = req.body as { fileName?: string; contentType?: string };

  if (!fileName) {
    return res.status(400).json({ message: 'fileName is required' });
  }

  const bucket = process.env.S3_BUCKET;
  if (!bucket) {
    return res.status(500).json({ message: 'S3 bucket not configured' });
  }

  const sanitizedFileName = fileName.replace(/[^a-zA-Z0-9_.-]/g, '_');
  const key = `uploads/${req.user?.sub ?? 'anonymous'}/${Date.now()}-${sanitizedFileName}`;
  const url = await createPresignedUploadUrl(bucket, key, { contentType });

  res.json({ url, key, bucket, contentType });
});

export default router;
