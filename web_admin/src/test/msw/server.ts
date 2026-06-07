import { setupServer } from 'msw/node';
import { adminApiHandlers } from './handlers';

export const server = setupServer(...adminApiHandlers);
