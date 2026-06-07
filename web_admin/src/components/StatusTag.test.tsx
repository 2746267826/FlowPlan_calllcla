import { screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { renderWithProviders } from '../test/render';
import { statusLabel } from '../utils/format';
import { StatusTag } from './StatusTag';

describe('StatusTag', () => {
  it('renders a successful status with the localized status label', () => {
    renderWithProviders(<StatusTag value="online" />);

    expect(screen.getByText(statusLabel('online'))).toHaveClass(
      'ant-tag-success',
    );
  });

  it('keeps unknown statuses visible to operators', () => {
    renderWithProviders(<StatusTag value="custom-state" />);

    expect(screen.getByText('custom-state')).toHaveClass('ant-tag');
  });
});
