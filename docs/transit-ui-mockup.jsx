import { useState } from "react";

const projects = [
  { name: "Transit", color: "#E8553A" },
  { name: "Prism", color: "#3A8FE8" },
  { name: "Zenith", color: "#48B865" },
  { name: "Meridian", color: "#C76FD4" },
  { name: "Orbit", color: "#F5A623" },
  { name: "Starwave", color: "#7B61FF" },
  { name: "Phase", color: "#00BCD4" },
  { name: "CloudForm", color: "#FF6B8A" },
  { name: "Fog CLI", color: "#8D9AA5" },
  { name: "Food Diary", color: "#A8D065" },
];

const sampleTasks = [
  { id: "T-1", name: "CloudKit schema design", project: 0, status: "idea", type: "feature" },
  { id: "T-2", name: "Mermaid offline cache", project: 1, status: "idea", type: "research" },
  { id: "T-14", name: "Screenshot parsing", project: 9, status: "idea", type: "research" },
  { id: "T-3", name: "Dashboard layout spec", project: 0, status: "planning", type: "feature" },
  { id: "T-4", name: "Tax year rollover", project: 2, status: "planning", type: "feature" },
  { id: "T-15", name: "Export format design", project: 6, status: "planning", type: "feature" },
  { id: "T-5", name: "App Intent schemas", project: 0, status: "spec", type: "feature" },
  { id: "T-6", name: "MarkdownUI table fix", project: 1, status: "spec", type: "bug" },
  { id: "T-7", name: "Kanban drag interactions", project: 0, status: "in-progress", type: "feature" },
  { id: "T-8", name: "HealthKit sync", project: 3, status: "in-progress", type: "feature" },
  { id: "T-9", name: "Location permission flow", project: 2, status: "in-progress", type: "chore" },
  { id: "T-13", name: "Stack deployment", project: 7, status: "in-progress", type: "feature" },
  { id: "T-10", name: "Project color picker", project: 0, status: "done", type: "feature" },
  { id: "T-11", name: "README update", project: 1, status: "done", type: "documentation" },
  { id: "T-12", name: "Legacy export format", project: 3, status: "abandoned", type: "feature" },
];

const allColumns = ["idea", "planning", "spec", "in-progress", "done"];
const columnLabels = { idea: "Idea", planning: "Planning", spec: "Spec", "in-progress": "In Progress", done: "Done / Abandoned" };
const typeBadgeColors = { feature: "#3898EC", bug: "#E8553A", chore: "#8E8E93", research: "#C76FD4", documentation: "#48B865" };

function hexToRgb(hex) {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return `${r}, ${g}, ${b}`;
}

function getColumnTasks(col, filterProjects) {
  let tasks;
  if (col === "done") tasks = sampleTasks.filter(t => t.status === "done" || t.status === "abandoned");
  else tasks = sampleTasks.filter(t => t.status === col);
  if (filterProjects && filterProjects.length > 0) tasks = tasks.filter(t => filterProjects.includes(t.project));
  return tasks;
}

// ─── Shared Components ───────────────────────────────────────

function TaskCard({ task, isSelected, onClick, isDark, isAbandoned, compact }) {
  const rgb = hexToRgb(projects[task.project].color);
  return (
    <div onClick={onClick} style={{
      borderRadius: compact ? 12 : 14, padding: compact ? "10px 12px" : "12px 14px",
      cursor: "pointer", transition: "all 0.25s cubic-bezier(0.25, 0.1, 0.25, 1)",
      opacity: isAbandoned ? 0.5 : 1,
      background: isDark ? "linear-gradient(135deg, rgba(255,255,255,0.08) 0%, rgba(255,255,255,0.03) 100%)" : "linear-gradient(135deg, rgba(255,255,255,0.85) 0%, rgba(255,255,255,0.55) 100%)",
      backdropFilter: "blur(40px) saturate(1.8)", WebkitBackdropFilter: "blur(40px) saturate(1.8)",
      border: `1.5px solid rgba(${rgb}, ${isDark ? 0.45 : 0.35})`,
      boxShadow: isSelected
        ? `0 0 0 2px rgba(${rgb}, ${isDark ? 0.6 : 0.5}), 0 8px 32px rgba(0,0,0,${isDark ? 0.3 : 0.08}), inset 0 1px 0 rgba(255,255,255,${isDark ? 0.08 : 0.5})`
        : `0 2px 12px rgba(0,0,0,${isDark ? 0.15 : 0.04}), 0 0.5px 0 rgba(255,255,255,${isDark ? 0.05 : 0.6}) inset`,
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: 7, marginBottom: compact ? 4 : 6 }}>
        <span style={{ fontSize: compact ? 11 : 11.5, color: isDark ? "rgba(255,255,255,0.55)" : "rgba(0,0,0,0.45)", fontWeight: 500 }}>{projects[task.project].name}</span>
        <span style={{ fontSize: compact ? 9.5 : 10, color: isDark ? "rgba(255,255,255,0.25)" : "rgba(0,0,0,0.22)", marginLeft: "auto", fontWeight: 500, fontVariantNumeric: "tabular-nums" }}>{task.id}</span>
      </div>
      <div style={{
        fontSize: compact ? 13 : 13.5, color: isDark ? "rgba(255,255,255,0.88)" : "rgba(0,0,0,0.82)",
        fontWeight: 400, lineHeight: 1.38,
        textDecoration: isAbandoned ? "line-through" : "none",
        textDecorationColor: isDark ? "rgba(255,255,255,0.25)" : "rgba(0,0,0,0.2)",
      }}>{task.name}</div>
      <div style={{ marginTop: compact ? 7 : 9 }}>
        <span style={{
          fontSize: compact ? 10 : 10.5, padding: compact ? "2px 7px" : "2.5px 8px", borderRadius: 6,
          background: isDark ? `rgba(${hexToRgb(typeBadgeColors[task.type])}, 0.15)` : `rgba(${hexToRgb(typeBadgeColors[task.type])}, 0.1)`,
          color: typeBadgeColors[task.type], fontWeight: 500,
        }}>{task.type}</span>
      </div>
    </div>
  );
}

function GlassButton({ onClick, isDark, size = 32, children, isActive, style = {} }) {
  return (
    <button onClick={onClick} style={{
      height: size, minWidth: size, borderRadius: size * 0.31,
      display: "flex", alignItems: "center", justifyContent: "center",
      border: "none", cursor: "pointer", padding: "0 9px",
      background: isActive
        ? isDark ? "rgba(56,143,232,0.2)" : "rgba(56,143,232,0.1)"
        : isDark ? "linear-gradient(135deg, rgba(255,255,255,0.1) 0%, rgba(255,255,255,0.04) 100%)" : "linear-gradient(135deg, rgba(255,255,255,0.8) 0%, rgba(255,255,255,0.5) 100%)",
      backdropFilter: "blur(30px) saturate(1.5)", WebkitBackdropFilter: "blur(30px) saturate(1.5)",
      boxShadow: isDark ? "0 1px 4px rgba(0,0,0,0.15), inset 0 0.5px 0 rgba(255,255,255,0.08)" : "0 1px 4px rgba(0,0,0,0.04), inset 0 0.5px 0 rgba(255,255,255,0.7)",
      color: isActive ? "#3898EC" : (isDark ? "rgba(255,255,255,0.6)" : "rgba(0,0,0,0.45)"),
      fontSize: size * 0.5, fontWeight: 300, gap: 4,
      ...style,
    }}>{children}</button>
  );
}

function GearIcon({ size = 16 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
    </svg>
  );
}

function FilterIcon({ size = 15 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3" />
    </svg>
  );
}

function BackChevron({ size = 10 }) {
  return (
    <svg width={size} height={size * 1.6} viewBox="0 0 10 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="8 2 2 8 8 14" />
    </svg>
  );
}

function AbandonedSeparator({ isDark }) {
  return (
    <div style={{ margin: "4px 0 2px", display: "flex", alignItems: "center", gap: 10, padding: "0 4px" }}>
      <div style={{ height: 0.5, flex: 1, background: isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.08)" }} />
      <span style={{ fontSize: 10, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.08em", color: isDark ? "rgba(255,255,255,0.2)" : "rgba(0,0,0,0.22)" }}>Abandoned</span>
      <div style={{ height: 0.5, flex: 1, background: isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.08)" }} />
    </div>
  );
}

function FilterPopover({ isDark, filterProjects, setFilterProjects, onClose, compact }) {
  const toggleProject = (i) => {
    if (filterProjects.includes(i)) setFilterProjects(filterProjects.filter(p => p !== i));
    else setFilterProjects([...filterProjects, i]);
  };
  return (
    <div onClick={onClose} style={{ position: "absolute", inset: 0, zIndex: 90, borderRadius: compact ? 32 : 0 }}>
      <div onClick={e => e.stopPropagation()} style={{
        position: "absolute", top: compact ? 92 : 60, right: compact ? 16 : 20,
        width: compact ? "calc(100% - 32px)" : 220,
        background: isDark ? "linear-gradient(160deg, rgba(50,50,58,0.92) 0%, rgba(35,35,42,0.92) 100%)" : "linear-gradient(160deg, rgba(255,255,255,0.95) 0%, rgba(248,248,250,0.92) 100%)",
        backdropFilter: "blur(60px) saturate(2)", WebkitBackdropFilter: "blur(60px) saturate(2)",
        borderRadius: 14, border: isDark ? "0.5px solid rgba(255,255,255,0.1)" : "0.5px solid rgba(0,0,0,0.08)",
        boxShadow: isDark ? "0 12px 40px rgba(0,0,0,0.4), inset 0 0.5px 0 rgba(255,255,255,0.06)" : "0 12px 40px rgba(0,0,0,0.12), inset 0 0.5px 0 rgba(255,255,255,0.8)",
        padding: "10px 6px", maxHeight: 300, overflowY: "auto",
      }}>
        <div style={{ padding: "4px 10px 8px", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span style={{ fontSize: 11, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.06em", color: isDark ? "rgba(255,255,255,0.35)" : "rgba(0,0,0,0.35)" }}>Filter by project</span>
          {filterProjects.length > 0 && (
            <button onClick={() => setFilterProjects([])} style={{ fontSize: 11, color: "#3898EC", background: "none", border: "none", cursor: "pointer", fontWeight: 500, padding: 0 }}>Clear</button>
          )}
        </div>
        {projects.map((p, i) => {
          const active = filterProjects.includes(i);
          return (
            <button key={i} onClick={() => toggleProject(i)} style={{
              display: "flex", alignItems: "center", gap: 8, width: "100%", padding: "8px 10px", borderRadius: 8,
              border: "none", cursor: "pointer", textAlign: "left",
              background: active ? (isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.04)") : "transparent",
            }}>
              <div style={{
                width: 18, height: 18, borderRadius: 5, display: "flex", alignItems: "center", justifyContent: "center",
                background: active ? p.color : "transparent",
                border: active ? "none" : isDark ? "1.5px solid rgba(255,255,255,0.15)" : "1.5px solid rgba(0,0,0,0.12)",
              }}>{active && <span style={{ color: "#FFF", fontSize: 11, fontWeight: 700 }}>✓</span>}</div>
              <div style={{ width: 8, height: 8, borderRadius: 4, background: p.color, flexShrink: 0 }} />
              <span style={{ fontSize: 13, fontWeight: active ? 500 : 400, color: isDark ? "rgba(255,255,255,0.8)" : "rgba(0,0,0,0.7)" }}>{p.name}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

function DetailModal({ task, isDark, onClose, compact }) {
  if (!task) return null;
  const rgb = hexToRgb(projects[task.project].color);
  return (
    <div onClick={onClose} style={{
      position: "absolute", inset: 0,
      background: isDark ? "rgba(0,0,0,0.45)" : "rgba(0,0,0,0.18)",
      backdropFilter: "blur(20px) saturate(1.5)", WebkitBackdropFilter: "blur(20px) saturate(1.5)",
      display: "flex", alignItems: compact ? "flex-end" : "center", justifyContent: "center",
      zIndex: 100, borderRadius: compact ? 32 : 0,
    }}>
      <div onClick={e => e.stopPropagation()} style={{
        background: isDark ? "linear-gradient(160deg, rgba(60,60,68,0.75) 0%, rgba(40,40,48,0.7) 100%)" : "linear-gradient(160deg, rgba(255,255,255,0.88) 0%, rgba(248,248,250,0.8) 100%)",
        backdropFilter: "blur(60px) saturate(2)", WebkitBackdropFilter: "blur(60px) saturate(2)",
        borderRadius: compact ? "20px 20px 0 0" : 20,
        border: `1.5px solid rgba(${rgb}, ${isDark ? 0.4 : 0.3})`,
        borderBottom: compact ? "none" : undefined,
        padding: compact ? "22px 20px 34px" : "26px 26px 22px",
        width: compact ? "100%" : 380, maxWidth: compact ? "100%" : "90vw",
        boxShadow: isDark ? "0 -8px 40px rgba(0,0,0,0.3), inset 0 1px 0 rgba(255,255,255,0.08)" : "0 -8px 40px rgba(0,0,0,0.08), inset 0 1px 0 rgba(255,255,255,0.8)",
      }}>
        {compact && <div style={{ width: 36, height: 4, borderRadius: 2, background: isDark ? "rgba(255,255,255,0.2)" : "rgba(0,0,0,0.15)", margin: "0 auto 16px" }} />}
        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 4 }}>
          <div style={{ width: 10, height: 10, borderRadius: 5, background: projects[task.project].color, boxShadow: `0 0 8px rgba(${rgb}, 0.4)` }} />
          <span style={{ fontSize: 13, fontWeight: 500, color: isDark ? "rgba(255,255,255,0.5)" : "rgba(0,0,0,0.45)" }}>{projects[task.project].name}</span>
          <span style={{ fontSize: 12, fontWeight: 500, color: isDark ? "rgba(255,255,255,0.25)" : "rgba(0,0,0,0.22)", marginLeft: "auto" }}>{task.id}</span>
        </div>
        <h2 style={{ fontSize: compact ? 19 : 21, fontWeight: 600, color: isDark ? "rgba(255,255,255,0.92)" : "rgba(0,0,0,0.85)", margin: "12px 0 14px", letterSpacing: "-0.02em", lineHeight: 1.25 }}>{task.name}</h2>
        <div style={{ display: "flex", gap: 8, marginBottom: 18 }}>
          <span style={{ fontSize: 11, padding: "4px 10px", borderRadius: 8, background: isDark ? `rgba(${hexToRgb(typeBadgeColors[task.type])}, 0.18)` : `rgba(${hexToRgb(typeBadgeColors[task.type])}, 0.1)`, color: typeBadgeColors[task.type], fontWeight: 500 }}>{task.type}</span>
          <span style={{ fontSize: 11, padding: "4px 10px", borderRadius: 8, background: isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.05)", color: isDark ? "rgba(255,255,255,0.55)" : "rgba(0,0,0,0.5)", fontWeight: 500 }}>{columnLabels[task.status] || task.status}</span>
        </div>
        <div style={{ fontSize: 13.5, lineHeight: 1.65, marginBottom: 18, color: isDark ? "rgba(255,255,255,0.45)" : "rgba(0,0,0,0.42)" }}>Task description and editing controls would appear here.</div>
        <div style={{ background: isDark ? "rgba(255,255,255,0.04)" : "rgba(0,0,0,0.03)", borderRadius: 10, padding: "10px 12px", marginBottom: 16 }}>
          <div style={{ fontSize: 10, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.08em", marginBottom: 8, color: isDark ? "rgba(255,255,255,0.25)" : "rgba(0,0,0,0.3)" }}>Metadata</div>
          <div style={{ display: "flex", justifyContent: "space-between" }}>
            <span style={{ fontSize: 12, color: isDark ? "rgba(255,255,255,0.35)" : "rgba(0,0,0,0.35)" }}>git.branch</span>
            <span style={{ fontSize: 12, fontWeight: 500, color: isDark ? "rgba(255,255,255,0.65)" : "rgba(0,0,0,0.6)" }}>feature/cloudkit-schema</span>
          </div>
        </div>
        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}>
          <button style={{ padding: "7px 16px", borderRadius: 10, border: "none", background: isDark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.06)", color: isDark ? "rgba(255,255,255,0.65)" : "rgba(0,0,0,0.55)", fontSize: 13, fontWeight: 500, cursor: "pointer" }}>Edit</button>
          <button style={{ padding: "7px 16px", borderRadius: 10, border: "none", background: isDark ? "rgba(232,85,58,0.2)" : "rgba(232,85,58,0.1)", color: "#E8553A", fontSize: 13, fontWeight: 500, cursor: "pointer" }}>Abandon</button>
        </div>
      </div>
    </div>
  );
}

function AddTaskSheet({ isDark, onClose, compact }) {
  const [selectedProject, setSelectedProject] = useState(0);
  const [pickerOpen, setPickerOpen] = useState(false);
  return (
    <div onClick={onClose} style={{
      position: "absolute", inset: 0,
      background: isDark ? "rgba(0,0,0,0.45)" : "rgba(0,0,0,0.18)",
      backdropFilter: "blur(20px) saturate(1.5)", WebkitBackdropFilter: "blur(20px) saturate(1.5)",
      display: "flex", alignItems: compact ? "flex-end" : "center", justifyContent: "center",
      zIndex: 100, borderRadius: compact ? 32 : 0,
    }}>
      <div onClick={e => e.stopPropagation()} style={{
        background: isDark ? "linear-gradient(160deg, rgba(60,60,68,0.75) 0%, rgba(40,40,48,0.7) 100%)" : "linear-gradient(160deg, rgba(255,255,255,0.88) 0%, rgba(248,248,250,0.8) 100%)",
        backdropFilter: "blur(60px) saturate(2)", WebkitBackdropFilter: "blur(60px) saturate(2)",
        borderRadius: compact ? "20px 20px 0 0" : 20,
        border: isDark ? "1px solid rgba(255,255,255,0.1)" : "1px solid rgba(0,0,0,0.06)",
        borderBottom: compact ? "none" : undefined,
        padding: compact ? "22px 20px 34px" : "26px 26px 22px",
        width: compact ? "100%" : 400, maxWidth: compact ? "100%" : "90vw",
        boxShadow: isDark ? "0 -8px 40px rgba(0,0,0,0.3), inset 0 1px 0 rgba(255,255,255,0.08)" : "0 -8px 40px rgba(0,0,0,0.08), inset 0 1px 0 rgba(255,255,255,0.8)",
      }}>
        {compact && <div style={{ width: 36, height: 4, borderRadius: 2, background: isDark ? "rgba(255,255,255,0.2)" : "rgba(0,0,0,0.15)", margin: "0 auto 16px" }} />}
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 22 }}>
          <h2 style={{ fontSize: compact ? 19 : 21, fontWeight: 600, color: isDark ? "rgba(255,255,255,0.92)" : "rgba(0,0,0,0.85)", margin: 0 }}>New Task</h2>
          <button onClick={onClose} style={{ width: 28, height: 28, borderRadius: 14, background: isDark ? "rgba(255,255,255,0.1)" : "rgba(0,0,0,0.06)", border: "none", cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", color: isDark ? "rgba(255,255,255,0.5)" : "rgba(0,0,0,0.4)", fontSize: 14 }}>✕</button>
        </div>
        <label style={{ fontSize: 12, fontWeight: 600, color: isDark ? "rgba(255,255,255,0.4)" : "rgba(0,0,0,0.35)", textTransform: "uppercase", letterSpacing: "0.06em", display: "block", marginBottom: 6 }}>Project</label>
        <div style={{ position: "relative", marginBottom: 16 }}>
          <button onClick={() => setPickerOpen(!pickerOpen)} style={{
            width: "100%", padding: "10px 12px", borderRadius: 10,
            background: isDark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.03)",
            border: pickerOpen ? (isDark ? "1px solid rgba(56,143,232,0.4)" : "1px solid rgba(56,143,232,0.3)") : (isDark ? "0.5px solid rgba(255,255,255,0.08)" : "0.5px solid rgba(0,0,0,0.06)"),
            cursor: "pointer", display: "flex", alignItems: "center", gap: 8, textAlign: "left",
          }}>
            <div style={{ width: 10, height: 10, borderRadius: 5, background: projects[selectedProject].color, flexShrink: 0 }} />
            <span style={{ fontSize: 14, color: isDark ? "rgba(255,255,255,0.85)" : "rgba(0,0,0,0.75)", fontWeight: 400, flex: 1 }}>{projects[selectedProject].name}</span>
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke={isDark ? "rgba(255,255,255,0.3)" : "rgba(0,0,0,0.25)"} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" style={{ transform: pickerOpen ? "rotate(180deg)" : "none", transition: "transform 0.2s ease" }}>
              <polyline points="6 9 12 15 18 9" />
            </svg>
          </button>
          {pickerOpen && (
            <div style={{
              position: "absolute", top: "calc(100% + 4px)", left: 0, right: 0, zIndex: 10,
              background: isDark ? "rgba(45,45,52,0.96)" : "rgba(255,255,255,0.96)",
              backdropFilter: "blur(40px)", borderRadius: 12, padding: "4px",
              border: isDark ? "0.5px solid rgba(255,255,255,0.1)" : "0.5px solid rgba(0,0,0,0.08)",
              boxShadow: isDark ? "0 8px 32px rgba(0,0,0,0.4)" : "0 8px 32px rgba(0,0,0,0.1)",
              maxHeight: 200, overflowY: "auto",
            }}>
              {projects.map((p, i) => (
                <button key={i} onClick={() => { setSelectedProject(i); setPickerOpen(false); }} style={{
                  display: "flex", alignItems: "center", gap: 8, width: "100%", padding: "8px 10px", borderRadius: 8, border: "none", cursor: "pointer", textAlign: "left",
                  background: i === selectedProject ? (isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.04)") : "transparent",
                }}>
                  <div style={{ width: 10, height: 10, borderRadius: 5, background: p.color, flexShrink: 0 }} />
                  <span style={{ fontSize: 13, color: isDark ? "rgba(255,255,255,0.8)" : "rgba(0,0,0,0.7)", fontWeight: i === selectedProject ? 500 : 400 }}>{p.name}</span>
                  {i === selectedProject && <span style={{ marginLeft: "auto", color: "#3898EC", fontSize: 13, fontWeight: 600 }}>✓</span>}
                </button>
              ))}
            </div>
          )}
        </div>
        <label style={{ fontSize: 12, fontWeight: 600, color: isDark ? "rgba(255,255,255,0.4)" : "rgba(0,0,0,0.35)", textTransform: "uppercase", letterSpacing: "0.06em", display: "block", marginBottom: 6 }}>Name</label>
        <div style={{ padding: "10px 12px", borderRadius: 10, marginBottom: 16, background: isDark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.03)", border: isDark ? "0.5px solid rgba(255,255,255,0.08)" : "0.5px solid rgba(0,0,0,0.06)", color: isDark ? "rgba(255,255,255,0.25)" : "rgba(0,0,0,0.25)", fontSize: 14 }}>Task name...</div>
        <label style={{ fontSize: 12, fontWeight: 600, color: isDark ? "rgba(255,255,255,0.4)" : "rgba(0,0,0,0.35)", textTransform: "uppercase", letterSpacing: "0.06em", display: "block", marginBottom: 6 }}>Description</label>
        <div style={{ padding: "10px 12px", borderRadius: 10, marginBottom: 16, background: isDark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.03)", border: isDark ? "0.5px solid rgba(255,255,255,0.08)" : "0.5px solid rgba(0,0,0,0.06)", color: isDark ? "rgba(255,255,255,0.25)" : "rgba(0,0,0,0.25)", fontSize: 14, minHeight: 56 }}>Description...</div>
        <label style={{ fontSize: 12, fontWeight: 600, color: isDark ? "rgba(255,255,255,0.4)" : "rgba(0,0,0,0.35)", textTransform: "uppercase", letterSpacing: "0.06em", display: "block", marginBottom: 6 }}>Type</label>
        <div style={{ display: "flex", gap: 6, marginBottom: 22, flexWrap: "wrap" }}>
          {Object.entries(typeBadgeColors).map(([type, color], i) => (
            <button key={type} style={{
              padding: "5px 10px", borderRadius: 7, cursor: "pointer", textTransform: "capitalize",
              border: i === 0 ? `1.5px solid ${color}50` : isDark ? "1px solid rgba(255,255,255,0.08)" : "1px solid rgba(0,0,0,0.06)",
              background: i === 0 ? `rgba(${hexToRgb(color)}, ${isDark ? 0.15 : 0.1})` : "transparent",
              color: i === 0 ? color : (isDark ? "rgba(255,255,255,0.4)" : "rgba(0,0,0,0.35)"),
              fontSize: 11, fontWeight: 500,
            }}>{type}</button>
          ))}
        </div>
        <button style={{
          width: "100%", padding: "12px", borderRadius: 12, border: "none", cursor: "pointer",
          background: isDark ? "rgba(56,143,232,0.25)" : "rgba(56,143,232,0.12)",
          color: "#3898EC", fontSize: 15, fontWeight: 600,
          boxShadow: isDark ? "inset 0 0.5px 0 rgba(255,255,255,0.1)" : "inset 0 0.5px 0 rgba(255,255,255,0.5)",
        }}>Create Task</button>
      </div>
    </div>
  );
}

// ─── Settings View ───────────────────────────────────────────
function SettingsView({ isDark, compact, onBack }) {
  return (
    <div style={{
      fontFamily: "-apple-system, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', sans-serif",
      minHeight: "100%", padding: compact ? "0 16px 20px" : "24px 20px",
      position: "relative", overflow: "hidden",
      background: isDark ? "#000" : "#F2F2F7",
    }}>
      {/* Nav bar with back button */}
      <div style={{
        display: "flex", alignItems: "center", gap: 6,
        marginBottom: compact ? 16 : 22,
        padding: compact ? "0" : "0",
      }}>
        <button onClick={onBack} style={{
          display: "flex", alignItems: "center", padding: "6px 8px",
          background: "none", border: "none", cursor: "pointer",
          color: "#3898EC",
        }}>
          <BackChevron size={12} />
        </button>
      </div>

      {!compact && (
        <h1 style={{ fontSize: 30, fontWeight: 700, color: isDark ? "rgba(255,255,255,0.92)" : "rgba(0,0,0,0.85)", margin: "0 0 22px", letterSpacing: "-0.02em" }}>Settings</h1>
      )}
      {compact && (
        <h1 style={{ fontSize: 28, fontWeight: 700, color: isDark ? "rgba(255,255,255,0.92)" : "rgba(0,0,0,0.85)", margin: "0 0 16px", letterSpacing: "-0.02em" }}>Settings</h1>
      )}

      {/* Projects section */}
      <div style={{ marginBottom: 28 }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 10, padding: "0 4px" }}>
          <span style={{ fontSize: 13, fontWeight: 600, color: isDark ? "rgba(255,255,255,0.45)" : "rgba(0,0,0,0.4)", textTransform: "uppercase", letterSpacing: "0.06em" }}>Projects</span>
          <GlassButton onClick={() => {}} isDark={isDark} size={26}>
            <span style={{ fontSize: 15, fontWeight: 300 }}>+</span>
          </GlassButton>
        </div>
        <div style={{
          borderRadius: 12, overflow: "hidden",
          background: isDark ? "linear-gradient(135deg, rgba(255,255,255,0.06) 0%, rgba(255,255,255,0.02) 100%)" : "linear-gradient(135deg, rgba(255,255,255,0.8) 0%, rgba(255,255,255,0.5) 100%)",
          backdropFilter: "blur(30px) saturate(1.5)", WebkitBackdropFilter: "blur(30px) saturate(1.5)",
          border: isDark ? "0.5px solid rgba(255,255,255,0.08)" : "0.5px solid rgba(255,255,255,0.6)",
          boxShadow: isDark ? "0 1px 4px rgba(0,0,0,0.15), inset 0 0.5px 0 rgba(255,255,255,0.05)" : "0 1px 4px rgba(0,0,0,0.03), inset 0 0.5px 0 rgba(255,255,255,0.8)",
        }}>
          {projects.map((p, i) => {
            const taskCount = sampleTasks.filter(t => t.project === i && t.status !== "done" && t.status !== "abandoned").length;
            return (
              <div key={i} style={{
                display: "flex", alignItems: "center", gap: 10,
                padding: compact ? "11px 14px" : "12px 16px",
                borderBottom: i < projects.length - 1 ? (isDark ? "0.5px solid rgba(255,255,255,0.05)" : "0.5px solid rgba(0,0,0,0.04)") : "none",
                cursor: "pointer",
              }}>
                <div style={{
                  width: 24, height: 24, borderRadius: 7, background: p.color,
                  display: "flex", alignItems: "center", justifyContent: "center",
                  boxShadow: `0 2px 8px rgba(${hexToRgb(p.color)}, 0.3)`,
                }}>
                  <span style={{ color: "#FFF", fontSize: 12, fontWeight: 700 }}>{p.name[0]}</span>
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 14, fontWeight: 400, color: isDark ? "rgba(255,255,255,0.85)" : "rgba(0,0,0,0.8)" }}>{p.name}</div>
                  <div style={{ fontSize: 11, color: isDark ? "rgba(255,255,255,0.3)" : "rgba(0,0,0,0.3)", marginTop: 1 }}>{taskCount} active task{taskCount !== 1 ? "s" : ""}</div>
                </div>
                <svg width="8" height="14" viewBox="0 0 8 14" fill="none" stroke={isDark ? "rgba(255,255,255,0.2)" : "rgba(0,0,0,0.2)"} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <polyline points="1 1 7 7 1 13" />
                </svg>
              </div>
            );
          })}
        </div>
      </div>

      {/* General section */}
      <div>
        <span style={{ fontSize: 13, fontWeight: 600, color: isDark ? "rgba(255,255,255,0.45)" : "rgba(0,0,0,0.4)", textTransform: "uppercase", letterSpacing: "0.06em", display: "block", marginBottom: 10, padding: "0 4px" }}>General</span>
        <div style={{
          borderRadius: 12, overflow: "hidden",
          background: isDark ? "linear-gradient(135deg, rgba(255,255,255,0.06) 0%, rgba(255,255,255,0.02) 100%)" : "linear-gradient(135deg, rgba(255,255,255,0.8) 0%, rgba(255,255,255,0.5) 100%)",
          backdropFilter: "blur(30px) saturate(1.5)", WebkitBackdropFilter: "blur(30px) saturate(1.5)",
          border: isDark ? "0.5px solid rgba(255,255,255,0.08)" : "0.5px solid rgba(255,255,255,0.6)",
          boxShadow: isDark ? "0 1px 4px rgba(0,0,0,0.15), inset 0 0.5px 0 rgba(255,255,255,0.05)" : "0 1px 4px rgba(0,0,0,0.03), inset 0 0.5px 0 rgba(255,255,255,0.8)",
        }}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: compact ? "11px 14px" : "12px 16px", borderBottom: isDark ? "0.5px solid rgba(255,255,255,0.05)" : "0.5px solid rgba(0,0,0,0.04)" }}>
            <span style={{ fontSize: 14, color: isDark ? "rgba(255,255,255,0.85)" : "rgba(0,0,0,0.8)" }}>About Transit</span>
            <span style={{ fontSize: 13, color: isDark ? "rgba(255,255,255,0.3)" : "rgba(0,0,0,0.3)" }}>v1.0</span>
          </div>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: compact ? "11px 14px" : "12px 16px" }}>
            <span style={{ fontSize: 14, color: isDark ? "rgba(255,255,255,0.85)" : "rgba(0,0,0,0.8)" }}>iCloud Sync</span>
            <div style={{ width: 42, height: 26, borderRadius: 13, padding: 2, background: "#48B865", display: "flex", alignItems: "center", justifyContent: "flex-end" }}>
              <div style={{ width: 22, height: 22, borderRadius: 11, background: "#FFF", boxShadow: "0 1px 3px rgba(0,0,0,0.15)" }} />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── Desktop/Tablet View ─────────────────────────────────────
function DesktopView({ isDark }) {
  const [selectedTask, setSelectedTask] = useState(null);
  const [showAddTask, setShowAddTask] = useState(false);
  const [showFilter, setShowFilter] = useState(false);
  const [filterProjects, setFilterProjects] = useState([]);
  const [showSettings, setShowSettings] = useState(false);
  const task = sampleTasks.find(t => t.id === selectedTask);

  return (
    <div style={{
      fontFamily: "-apple-system, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', sans-serif",
      height: "100%", display: "flex", flexDirection: "column",
      background: isDark ? "#000" : "#F2F2F7", position: "relative", overflow: "hidden",
    }}>
      <div style={{ position: "absolute", top: -60, right: -40, width: 280, height: 280, background: isDark ? "radial-gradient(circle, rgba(56,143,232,0.08) 0%, transparent 70%)" : "radial-gradient(circle, rgba(56,143,232,0.12) 0%, transparent 70%)", pointerEvents: "none", filter: "blur(30px)" }} />
      <div style={{ position: "absolute", bottom: -40, left: -60, width: 300, height: 300, background: isDark ? "radial-gradient(circle, rgba(199,111,212,0.06) 0%, transparent 70%)" : "radial-gradient(circle, rgba(199,111,212,0.1) 0%, transparent 70%)", pointerEvents: "none", filter: "blur(30px)" }} />

      <div style={{ flex: 1, overflow: "auto" }}>
        {showSettings ? (
          <SettingsView isDark={isDark} onBack={() => setShowSettings(false)} />
        ) : (
          <div style={{ padding: "24px 20px" }}>
            <div style={{ marginBottom: 22, display: "flex", alignItems: "center", justifyContent: "space-between", position: "relative" }}>
              <h1 style={{ fontSize: 30, fontWeight: 700, color: isDark ? "rgba(255,255,255,0.92)" : "rgba(0,0,0,0.85)", margin: 0, letterSpacing: "-0.02em" }}>Transit</h1>
              <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <GlassButton onClick={() => setShowFilter(!showFilter)} isDark={isDark} isActive={filterProjects.length > 0}>
                  <FilterIcon />
                  {filterProjects.length > 0 && <span style={{ fontSize: 11, fontWeight: 600 }}>{filterProjects.length}</span>}
                </GlassButton>
                <GlassButton onClick={() => setShowAddTask(true)} isDark={isDark}>
                  <span style={{ fontSize: 18, fontWeight: 300 }}>+</span>
                </GlassButton>
                <GlassButton onClick={() => setShowSettings(true)} isDark={isDark}><GearIcon size={16} /></GlassButton>
              </div>
            </div>
            <div style={{ display: "flex", gap: 12, overflowX: "auto", paddingBottom: 12, position: "relative" }}>
              {allColumns.map((col) => {
                const tasks = getColumnTasks(col, filterProjects.length > 0 ? filterProjects : null);
                const abandoned = tasks.filter(t => t.status === "abandoned");
                const active = tasks.filter(t => t.status !== "abandoned");
                return (
                  <div key={col} style={{ flex: "1 0 185px", minWidth: 185, maxWidth: 245 }}>
                    <div style={{
                      display: "flex", alignItems: "center", gap: 8, marginBottom: 12, padding: "8px 12px", borderRadius: 10,
                      background: isDark ? "linear-gradient(135deg, rgba(255,255,255,0.06) 0%, rgba(255,255,255,0.02) 100%)" : "linear-gradient(135deg, rgba(255,255,255,0.7) 0%, rgba(255,255,255,0.4) 100%)",
                      backdropFilter: "blur(30px) saturate(1.5)",
                      border: isDark ? "0.5px solid rgba(255,255,255,0.08)" : "0.5px solid rgba(255,255,255,0.6)",
                      boxShadow: isDark ? "0 1px 4px rgba(0,0,0,0.15), inset 0 0.5px 0 rgba(255,255,255,0.05)" : "0 1px 4px rgba(0,0,0,0.03), inset 0 0.5px 0 rgba(255,255,255,0.8)",
                    }}>
                      <span style={{ fontSize: 13, fontWeight: 600, color: isDark ? "rgba(255,255,255,0.7)" : "rgba(0,0,0,0.55)" }}>{columnLabels[col]}</span>
                      <span style={{ fontSize: 12, fontWeight: 600, marginLeft: "auto", color: isDark ? "rgba(255,255,255,0.25)" : "rgba(0,0,0,0.22)", fontVariantNumeric: "tabular-nums" }}>{tasks.length}</span>
                    </div>
                    <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                      {(col === "done" ? active : tasks).map(t => (
                        <TaskCard key={t.id} task={t} isSelected={selectedTask === t.id} onClick={() => setSelectedTask(t.id)} isDark={isDark} isAbandoned={false} />
                      ))}
                      {col === "done" && abandoned.length > 0 && (
                        <><AbandonedSeparator isDark={isDark} />{abandoned.map(t => (
                          <TaskCard key={t.id} task={t} isSelected={selectedTask === t.id} onClick={() => setSelectedTask(t.id)} isDark={isDark} isAbandoned={true} />
                        ))}</>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>

      {showFilter && <FilterPopover isDark={isDark} filterProjects={filterProjects} setFilterProjects={setFilterProjects} onClose={() => setShowFilter(false)} />}
      {showAddTask && <AddTaskSheet isDark={isDark} onClose={() => setShowAddTask(false)} />}
      <DetailModal task={task} isDark={isDark} onClose={() => setSelectedTask(null)} />
    </div>
  );
}

// ─── iPhone View ─────────────────────────────────────────────
function PhoneView({ isDark }) {
  const [currentCol, setCurrentCol] = useState(3);
  const [selectedTask, setSelectedTask] = useState(null);
  const [showAddTask, setShowAddTask] = useState(false);
  const [showFilter, setShowFilter] = useState(false);
  const [filterProjects, setFilterProjects] = useState([]);
  const [showSettings, setShowSettings] = useState(false);
  const task = sampleTasks.find(t => t.id === selectedTask);

  const col = allColumns[currentCol];
  const tasks = getColumnTasks(col, filterProjects.length > 0 ? filterProjects : null);
  const abandoned = tasks.filter(t => t.status === "abandoned");
  const active = tasks.filter(t => t.status !== "abandoned");
  const shortLabels = { idea: "Idea", planning: "Plan", spec: "Spec", "in-progress": "Active", done: "Done" };

  return (
    <div style={{
      fontFamily: "-apple-system, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', sans-serif",
      height: "100%", display: "flex", flexDirection: "column",
      position: "relative", overflow: "hidden",
      background: isDark ? "#000" : "#F2F2F7",
    }}>
      <div style={{ position: "absolute", top: -40, right: -30, width: 200, height: 200, background: isDark ? "radial-gradient(circle, rgba(56,143,232,0.08) 0%, transparent 70%)" : "radial-gradient(circle, rgba(56,143,232,0.12) 0%, transparent 70%)", pointerEvents: "none", filter: "blur(25px)" }} />
      <div style={{ position: "absolute", bottom: 60, left: -40, width: 200, height: 200, background: isDark ? "radial-gradient(circle, rgba(199,111,212,0.06) 0%, transparent 70%)" : "radial-gradient(circle, rgba(199,111,212,0.1) 0%, transparent 70%)", pointerEvents: "none", filter: "blur(25px)" }} />

      {/* Status bar */}
      <div style={{ padding: "14px 24px 0", display: "flex", justifyContent: "space-between", alignItems: "center", flexShrink: 0 }}>
        <span style={{ fontSize: 15, fontWeight: 600, color: isDark ? "rgba(255,255,255,0.85)" : "rgba(0,0,0,0.8)" }}>9:41</span>
        <div style={{ display: "flex", gap: 5, alignItems: "center" }}>
          <div style={{ display: "flex", gap: 1 }}>{[4,6,8,10].map((h,i) => (<div key={i} style={{ width: 3, height: h, borderRadius: 1, background: isDark ? "rgba(255,255,255,0.7)" : "rgba(0,0,0,0.6)" }} />))}</div>
          <span style={{ fontSize: 12, color: isDark ? "rgba(255,255,255,0.7)" : "rgba(0,0,0,0.6)", fontWeight: 500, marginLeft: 2 }}>5G</span>
          <svg width="24" height="12" viewBox="0 0 24 12" style={{ marginLeft: 2 }}><rect x="0" y="1" width="20" height="10" rx="2" fill="none" stroke={isDark ? "rgba(255,255,255,0.5)" : "rgba(0,0,0,0.4)"} strokeWidth="1"/><rect x="2" y="3" width="14" height="6" rx="1" fill={isDark ? "rgba(255,255,255,0.7)" : "rgba(0,0,0,0.6)"}/><rect x="21" y="4" width="2" height="4" rx="0.5" fill={isDark ? "rgba(255,255,255,0.3)" : "rgba(0,0,0,0.25)"}/></svg>
        </div>
      </div>

      {showSettings ? (
        <div style={{ flex: 1, overflowY: "auto", padding: "12px 0 0" }}>
          <SettingsView isDark={isDark} compact onBack={() => setShowSettings(false)} />
        </div>
      ) : (
        <>
          {/* Nav */}
          <div style={{ padding: "16px 20px 12px", display: "flex", alignItems: "center", justifyContent: "space-between", flexShrink: 0 }}>
            <h1 style={{ fontSize: 28, fontWeight: 700, color: isDark ? "rgba(255,255,255,0.92)" : "rgba(0,0,0,0.85)", margin: 0, letterSpacing: "-0.02em" }}>Transit</h1>
            <div style={{ display: "flex", gap: 8 }}>
              <GlassButton onClick={() => setShowFilter(!showFilter)} isDark={isDark} size={30} isActive={filterProjects.length > 0}>
                <FilterIcon size={13} />
                {filterProjects.length > 0 && <span style={{ fontSize: 10, fontWeight: 600 }}>{filterProjects.length}</span>}
              </GlassButton>
              <GlassButton onClick={() => setShowAddTask(true)} isDark={isDark} size={30}>
                <span style={{ fontSize: 17, fontWeight: 300 }}>+</span>
              </GlassButton>
              <GlassButton onClick={() => setShowSettings(true)} isDark={isDark} size={30}><GearIcon size={14} /></GlassButton>
            </div>
          </div>

          {/* Segmented control */}
          <div style={{ padding: "0 16px", marginBottom: 16, flexShrink: 0 }}>
            <div style={{
              display: "flex", borderRadius: 10, padding: 2,
              background: isDark ? "linear-gradient(135deg, rgba(255,255,255,0.07) 0%, rgba(255,255,255,0.03) 100%)" : "linear-gradient(135deg, rgba(255,255,255,0.6) 0%, rgba(255,255,255,0.35) 100%)",
              backdropFilter: "blur(30px) saturate(1.5)",
              border: isDark ? "0.5px solid rgba(255,255,255,0.06)" : "0.5px solid rgba(255,255,255,0.5)",
              boxShadow: isDark ? "0 1px 4px rgba(0,0,0,0.12), inset 0 0.5px 0 rgba(255,255,255,0.04)" : "0 1px 4px rgba(0,0,0,0.03), inset 0 0.5px 0 rgba(255,255,255,0.7)",
            }}>
              {allColumns.map((c, i) => {
                const isActive = i === currentCol;
                const count = getColumnTasks(c, filterProjects.length > 0 ? filterProjects : null).length;
                return (
                  <button key={c} onClick={() => setCurrentCol(i)} style={{
                    flex: 1, padding: "7px 2px", borderRadius: 8, border: "none", cursor: "pointer",
                    background: isActive ? (isDark ? "linear-gradient(135deg, rgba(255,255,255,0.14) 0%, rgba(255,255,255,0.08) 100%)" : "linear-gradient(135deg, rgba(255,255,255,0.95) 0%, rgba(255,255,255,0.7) 100%)") : "transparent",
                    boxShadow: isActive ? (isDark ? "0 1px 6px rgba(0,0,0,0.2), inset 0 0.5px 0 rgba(255,255,255,0.08)" : "0 1px 6px rgba(0,0,0,0.06), inset 0 0.5px 0 rgba(255,255,255,0.9)") : "none",
                    display: "flex", flexDirection: "column", alignItems: "center", gap: 1, transition: "all 0.2s ease",
                  }}>
                    <span style={{ fontSize: 10.5, fontWeight: isActive ? 600 : 500, color: isActive ? (isDark ? "rgba(255,255,255,0.85)" : "rgba(0,0,0,0.75)") : (isDark ? "rgba(255,255,255,0.35)" : "rgba(0,0,0,0.3)") }}>{shortLabels[c]}</span>
                    <span style={{ fontSize: 9, fontWeight: 500, fontVariantNumeric: "tabular-nums", color: isActive ? (isDark ? "rgba(255,255,255,0.4)" : "rgba(0,0,0,0.3)") : (isDark ? "rgba(255,255,255,0.18)" : "rgba(0,0,0,0.15)") }}>{count}</span>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Task list */}
          <div style={{ flex: 1, overflowY: "auto", padding: "0 16px 8px", display: "flex", flexDirection: "column", gap: 8 }}>
            {(col === "done" ? active : tasks).map(t => (
              <TaskCard key={t.id} task={t} isSelected={selectedTask === t.id} onClick={() => setSelectedTask(t.id)} isDark={isDark} isAbandoned={false} compact />
            ))}
            {col === "done" && abandoned.length > 0 && (
              <><AbandonedSeparator isDark={isDark} />{abandoned.map(t => (
                <TaskCard key={t.id} task={t} isSelected={selectedTask === t.id} onClick={() => setSelectedTask(t.id)} isDark={isDark} isAbandoned={true} compact />
              ))}</>
            )}
            {tasks.length === 0 && (
              <div style={{ textAlign: "center", padding: "40px 20px", color: isDark ? "rgba(255,255,255,0.2)" : "rgba(0,0,0,0.2)", fontSize: 14 }}>No tasks in {columnLabels[col]}</div>
            )}
          </div>
        </>
      )}

      {/* Home indicator */}
      <div style={{ padding: "8px 0 6px", display: "flex", justifyContent: "center", flexShrink: 0 }}>
        <div style={{ width: 134, height: 5, borderRadius: 3, background: isDark ? "rgba(255,255,255,0.25)" : "rgba(0,0,0,0.2)" }} />
      </div>

      {showFilter && <FilterPopover isDark={isDark} filterProjects={filterProjects} setFilterProjects={setFilterProjects} onClose={() => setShowFilter(false)} compact />}
      {showAddTask && <AddTaskSheet isDark={isDark} onClose={() => setShowAddTask(false)} compact />}
      <DetailModal task={task} isDark={isDark} onClose={() => setSelectedTask(null)} compact />
    </div>
  );
}

// ─── Main ────────────────────────────────────────────────────
export default function TransitApp() {
  const [isDark, setIsDark] = useState(false);
  const [view, setView] = useState("desktop");

  return (
    <div style={{ height: "100vh", display: "flex", flexDirection: "column", background: isDark ? "#111" : "#E8E8ED", fontFamily: "-apple-system, sans-serif" }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 16, padding: "12px 16px", flexShrink: 0 }}>
        <div style={{ display: "flex", gap: 0 }}>
          {[["desktop", "iPad / Mac"], ["phone", "iPhone 17 Pro"]].map(([v, label], i) => (
            <button key={v} onClick={() => setView(v)} style={{
              padding: "6px 16px", borderRadius: i === 0 ? "8px 0 0 8px" : "0 8px 8px 0",
              border: `1px solid ${isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.12)"}`,
              borderLeft: i === 1 ? "none" : undefined,
              background: view === v ? (isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.08)") : "transparent",
              color: isDark ? "rgba(255,255,255,0.8)" : "rgba(0,0,0,0.7)",
              fontSize: 12, fontWeight: view === v ? 600 : 400, cursor: "pointer",
            }}>{label}</button>
          ))}
        </div>
        <div style={{ display: "flex", gap: 0 }}>
          {[[false, "☀️ Light"], [true, "🌙 Dark"]].map(([dark, label], i) => (
            <button key={String(dark)} onClick={() => setIsDark(dark)} style={{
              padding: "6px 16px", borderRadius: i === 0 ? "8px 0 0 8px" : "0 8px 8px 0",
              border: `1px solid ${isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.12)"}`,
              borderLeft: i === 1 ? "none" : undefined,
              background: isDark === dark ? (isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.08)") : "transparent",
              color: isDark ? "rgba(255,255,255,0.8)" : "rgba(0,0,0,0.7)",
              fontSize: 12, fontWeight: isDark === dark ? 600 : 400, cursor: "pointer",
            }}>{label}</button>
          ))}
        </div>
      </div>

      <div style={{ flex: 1, overflow: "hidden", display: "flex", alignItems: "center", justifyContent: "center", padding: view === "phone" ? "0 0 16px" : "0" }}>
        {view === "desktop" ? (
          <div style={{ width: "100%", height: "100%", overflow: "hidden" }}>
            <DesktopView isDark={isDark} />
          </div>
        ) : (
          <div style={{
            width: 283, height: 614, borderRadius: 32, overflow: "hidden",
            border: isDark ? "3px solid #333" : "3px solid #888",
            boxShadow: isDark ? "0 20px 60px rgba(0,0,0,0.5)" : "0 20px 60px rgba(0,0,0,0.2)",
            position: "relative", flexShrink: 0,
          }}>
            <div style={{ position: "absolute", top: 8, left: "50%", transform: "translateX(-50%)", width: 90, height: 24, borderRadius: 14, background: "#000", zIndex: 200 }} />
            <div style={{ width: "100%", height: "100%", overflow: "hidden" }}>
              <PhoneView isDark={isDark} />
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
