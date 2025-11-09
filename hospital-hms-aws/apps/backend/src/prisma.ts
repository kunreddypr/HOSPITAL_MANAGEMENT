import { PrismaClient } from '@prisma/client';

const { POSTGRES_HOST, POSTGRES_DB, POSTGRES_USER, DB_PASSWORD } = process.env;

if (!process.env.DATABASE_URL && POSTGRES_HOST && POSTGRES_DB && POSTGRES_USER && DB_PASSWORD) {
  process.env.DATABASE_URL = `postgresql://${POSTGRES_USER}:${DB_PASSWORD}@${POSTGRES_HOST}:5432/${POSTGRES_DB}?schema=public`;
}

const prisma = new PrismaClient();

export default prisma;
