export const TEST_USER_ID = '00000000-0000-4000-8000-000000000101';
export const TEST_DEVICE_ID = '00000000-0000-4000-8000-000000000102';
export const TEST_CLIENT_DEVICE_ID = 'flowplan-test-device';

export const TEST_HEADERS = {
  'x-flowplanv2-user-id': TEST_USER_ID,
  'x-flowplanv2-device-id': TEST_DEVICE_ID,
};

export const TEST_USER = {
  id: TEST_USER_ID,
  displayName: 'Test User',
};

export const TEST_DEVICE = {
  id: TEST_DEVICE_ID,
  deviceName: 'Test Device',
  platform: 'windows',
  clientDeviceId: TEST_CLIENT_DEVICE_ID,
};
