import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const swaggerMocks = vi.hoisted(() => ({
  createDocument: vi.fn(() => ({ openapi: '3.0.0' })),
  setup: vi.fn(),
}));

vi.mock('@nestjs/swagger', () => {
  class DocumentBuilder {
    setTitle() {
      return this;
    }

    setDescription() {
      return this;
    }

    setVersion() {
      return this;
    }

    addBearerAuth() {
      return this;
    }

    build() {
      return { title: 'FlowPlanV2 API' };
    }
  }

  return {
    DocumentBuilder,
    SwaggerModule: swaggerMocks,
  };
});

import { configureApp } from './app.bootstrap';

const ORIGINAL_ADMIN_CORS_ORIGIN = process.env.ADMIN_CORS_ORIGIN;
const ORIGINAL_FLOWPLANV2_BODY_LIMIT = process.env.FLOWPLANV2_BODY_LIMIT;

describe('configureApp', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    delete process.env.ADMIN_CORS_ORIGIN;
    delete process.env.FLOWPLANV2_BODY_LIMIT;
  });

  afterEach(() => {
    process.env.ADMIN_CORS_ORIGIN = ORIGINAL_ADMIN_CORS_ORIGIN;
    process.env.FLOWPLANV2_BODY_LIMIT = ORIGINAL_FLOWPLANV2_BODY_LIMIT;
  });

  it('configures API bootstrap behavior shared by main and API tests', () => {
    const app = {
      use: vi.fn(),
      enableCors: vi.fn(),
      setGlobalPrefix: vi.fn(),
      enableShutdownHooks: vi.fn(),
    };

    const configured = configureApp(app as never);

    expect(configured).toBe(app);
    expect(app.use).toHaveBeenCalledTimes(2);
    expect(app.enableCors).toHaveBeenCalledWith({
      origin: true,
      credentials: false,
    });
    expect(app.setGlobalPrefix).toHaveBeenCalledWith('api');
    expect(app.enableShutdownHooks).toHaveBeenCalled();
    expect(swaggerMocks.createDocument).toHaveBeenCalledWith(
      app,
      expect.any(Object),
    );
    expect(swaggerMocks.setup).toHaveBeenCalledWith(
      'api/docs',
      app,
      { openapi: '3.0.0' },
    );
  });
});
