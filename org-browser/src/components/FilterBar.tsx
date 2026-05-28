interface FilterBarProps {
  options: string[];
  value: string;
  onChange: (value: string) => void;
  allValue: string;
  totalCount: number;
  visibleCount: number;
}

export function FilterBar({
  options,
  value,
  onChange,
  allValue,
  totalCount,
  visibleCount,
}: FilterBarProps) {
  return (
    <div className="filter-bar">
      <label htmlFor="family-type">API Family Type</label>
      <select
        id="family-type"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      >
        <option value={allValue}>All ({totalCount})</option>
        {options.map((type) => (
          <option key={type} value={type}>
            {type}
          </option>
        ))}
      </select>
      <span className="filter-count">
        {visibleCount} of {totalCount} {totalCount === 1 ? 'org' : 'orgs'}
      </span>
    </div>
  );
}
