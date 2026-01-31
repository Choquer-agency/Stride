import { neon } from '@neondatabase/serverless';

// Initialize Neon client
const sql = neon(process.env.DATABASE_URL!);

export { sql };

// Helper to run queries with error handling
export async function query<T>(sqlQuery: string, params: unknown[] = []): Promise<T[]> {
  try {
    const result = await sql(sqlQuery, params);
    return result as T[];
  } catch (error) {
    console.error('Database query error:', error);
    throw error;
  }
}

// Helper for single row queries
export async function queryOne<T>(sqlQuery: string, params: unknown[] = []): Promise<T | null> {
  const results = await query<T>(sqlQuery, params);
  return results[0] || null;
}

// Helper for insert/update/delete that returns affected row
export async function execute(sqlQuery: string, params: unknown[] = []): Promise<void> {
  await sql(sqlQuery, params);
}
