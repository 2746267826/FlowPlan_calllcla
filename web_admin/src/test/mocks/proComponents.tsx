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
  loading?: boolean;
  rowKey?: string | ((row: RecordLike) => React.Key);
  rowSelection?: {
    selectedRowKeys?: React.Key[];
    onChange?: (keys: React.Key[]) => void;
  };
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

export function ProTable(props: ProTableProps) {
  const rows = props.dataSource ?? [];
  const columns = props.columns ?? [];
  const selected = props.rowSelection?.selectedRowKeys ?? [];

  return (
    <table>
      <thead>
        <tr>
          {props.rowSelection ? <th>Select</th> : null}
          {columns.map((column, index) => (
            <th key={index}>{column.title}</th>
          ))}
        </tr>
      </thead>
      <tbody>
        {props.loading ? (
          <tr>
            <td colSpan={columns.length + (props.rowSelection ? 1 : 0)}>
              Loading
            </td>
          </tr>
        ) : null}
        {rows.map((row, rowIndex) => {
          const key = resolveRowKey(row, props.rowKey);
          return (
            <tr key={String(key)}>
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
          );
        })}
      </tbody>
    </table>
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
