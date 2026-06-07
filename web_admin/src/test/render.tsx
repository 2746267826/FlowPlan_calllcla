import { App as AntdApp, ConfigProvider } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import { type ReactElement } from 'react';
import { render } from '@testing-library/react';

export function renderWithProviders(ui: ReactElement) {
  return render(
    <ConfigProvider locale={zhCN}>
      <AntdApp>{ui}</AntdApp>
    </ConfigProvider>,
  );
}
