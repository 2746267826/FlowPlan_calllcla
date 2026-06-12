import React, { type ReactNode } from 'react';

type RecordLike = Record<string, unknown>;

type Column = {
  title?: ReactNode;
  dataIndex?: string;
  render?: (value: unknown, row: RecordLike, index: number) => ReactNode;
};

type ProTableProps = {
  columns?: Column[];
  dataSource?: RecordLike[];
  expandable?: {
    expandedRowRender?: (row: RecordLike, index: number) => ReactNode;
  };
  loading?: boolean;
  rowKey?: string | ((row: RecordLike) => React.Key);
  rowSelection?: {
    selectedRowKeys?: React.Key[];
    onChange?: (keys: React.Key[]) => void;
  };
  tableAlertRender?: () => ReactNode;
};

function resolveRowKey(row: RecordLike, rowKey: ProTableProps['rowKey']) {
  if (typeof rowKey === 'function') return rowKey(row);
  if (typeof rowKey === 'string') return row[rowKey] as React.Key;
  return (row.key ?? row.id) as React.Key;
}

function readableRowName(row: RecordLike, key: React.Key) {
  return String(row.title ?? row.summary ?? row.name ?? key);
}

export function PageContainer(props: {
  title?: ReactNode;
  content?: ReactNode;
  extra?: ReactNode;
  loading?: boolean;
  children?: ReactNode;
}) {
  return (
    <section aria-label={String(props.title ?? 'page')}>
      <header>
        <h1>{props.title}</h1>
        {props.content ? <p>{props.content}</p> : null}
        {props.extra}
      </header>
      {props.loading ? <div role="status">Loading</div> : null}
      {props.children}
    </section>
  );
}

export function ProLayout(props: {
  children?: ReactNode;
  menuDataRender?: () => Array<{ path?: string; name?: ReactNode }>;
  menuExtraRender?: () => ReactNode;
  menuItemRender?: (
    item: { path?: string; name?: ReactNode },
    dom: ReactNode,
  ) => ReactNode;
  title?: ReactNode;
}) {
  const extraMenu =
    (
      globalThis as {
        __webAdminProLayoutExtraMenuItems?: Array<{
          path?: string;
          name?: ReactNode;
        }>;
      }
    ).__webAdminProLayoutExtraMenuItems ?? [];
  const menu = [...(props.menuDataRender?.() ?? []), ...extraMenu];
  return (
    <div>
      <aside>
        {props.title ? <strong>{props.title}</strong> : null}
        <nav>
          {menu.map((item) => {
            const label = item.name ?? item.path;
            const dom = <span>{label}</span>;
            return (
              <div key={String(item.path ?? label)}>
                {props.menuItemRender ? props.menuItemRender(item, dom) : dom}
              </div>
            );
          })}
        </nav>
        {props.menuExtraRender?.()}
      </aside>
      <main>{props.children}</main>
    </div>
  );
}

export function ProTable(props: ProTableProps) {
  const rows = props.dataSource ?? [];
  const columns = props.columns ?? [];
  const selected = props.rowSelection?.selectedRowKeys ?? [];

  return (
    <>
      {props.tableAlertRender ? (
        <div role="status">{props.tableAlertRender()}</div>
      ) : null}
      <table>
        <thead>
          <tr>
            {props.expandable?.expandedRowRender ? <th>Expand</th> : null}
            {props.rowSelection ? <th>Select</th> : null}
            {columns.map((column, index) => (
              <th key={index}>{column.title}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {props.loading ? (
            <tr>
              <td
                colSpan={
                  columns.length +
                  (props.rowSelection ? 1 : 0) +
                  (props.expandable?.expandedRowRender ? 1 : 0)
                }
              >
                Loading
              </td>
            </tr>
          ) : null}
          {rows.map((row, rowIndex) => {
            const key = resolveRowKey(row, props.rowKey);
            return (
              <React.Fragment key={String(key)}>
                <tr>
                  {props.expandable?.expandedRowRender ? (
                    <td>
                      <button
                        type="button"
                        aria-label={`Expand ${readableRowName(row, key)}`}
                        className="ant-table-row-expand-icon"
                      >
                        Expand
                      </button>
                    </td>
                  ) : null}
                  {props.rowSelection ? (
                    <td>
                      <input
                        aria-label={`Select ${readableRowName(row, key)}`}
                        checked={selected.includes(key)}
                        type="checkbox"
                        onChange={(event) => {
                          const next = event.currentTarget.checked
                            ? [...selected, key]
                            : selected.filter((item) => item !== key);
                          props.rowSelection?.onChange?.(next);
                        }}
                      />
                    </td>
                  ) : null}
                  {columns.map((column, columnIndex) => {
                    const value = column.dataIndex
                      ? row[column.dataIndex]
                      : undefined;
                    return (
                      <td key={columnIndex}>
                        {column.render
                          ? column.render(value, row, rowIndex)
                          : String(value ?? '')}
                      </td>
                    );
                  })}
                </tr>
                {props.expandable?.expandedRowRender ? (
                  <tr>
                    <td
                      colSpan={
                        columns.length +
                        (props.rowSelection ? 1 : 0) +
                        1
                      }
                    >
                      {props.expandable.expandedRowRender(row, rowIndex)}
                    </td>
                  </tr>
                ) : null}
              </React.Fragment>
            );
          })}
        </tbody>
      </table>
    </>
  );
}

function StatisticCardBase(props: {
  statistic?: { title?: ReactNode; value?: ReactNode };
}) {
  return (
    <article>
      <span>{props.statistic?.title}</span>
      <strong>{props.statistic?.value}</strong>
    </article>
  );
}

StatisticCardBase.Group = function StatisticCardGroup(props: {
  children?: ReactNode;
}) {
  return <div aria-label="statistics">{props.children}</div>;
};

export const StatisticCard = StatisticCardBase;

export function ProCard(props: {
  children?: ReactNode;
}) {
  return <div>{props.children}</div>;
}
