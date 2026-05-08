// Test setup — runs before each test file.

// Override DATABASE_URL for test database.
if (!process.env.FLOWPLANV2_DATABASE_URL && !process.env.DATABASE_URL) {
  process.env.DATABASE_URL =
    'postgres://postgres:060331@localhost:5432/flowplantest';
}
