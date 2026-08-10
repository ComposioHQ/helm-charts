// Shared Slack Block Kit helpers for the CVE audit reports, mirroring the
// layout conventions of the nightly release report (nightly-slack-summary.sh):
// header, mrkdwn sections, field grids, dividers, and context rows.

const SECTION_TEXT_LIMIT = 2900;

// Slack caps section text at 3000 chars; truncate defensively and keep any
// code fence balanced so a huge table cannot invalidate the payload.
function truncateSectionText(text) {
  if (text.length <= SECTION_TEXT_LIMIT) return text;
  let cut = text.slice(0, SECTION_TEXT_LIMIT);
  const lastNewline = cut.lastIndexOf("\n");
  if (lastNewline > 0) cut = cut.slice(0, lastNewline);
  const fenceCount = (cut.match(/^```/gm) || []).length;
  if (fenceCount % 2 === 1) cut += "\n```";
  return `${cut}\n_…truncated; full details in the audit artifact._`;
}

export function headerBlock(text) {
  return { type: "header", text: { type: "plain_text", text, emoji: true } };
}

export function sectionBlock(text) {
  return { type: "section", text: { type: "mrkdwn", text: truncateSectionText(text) } };
}

export function fieldsBlock(fields) {
  return { type: "section", fields: fields.map((text) => ({ type: "mrkdwn", text })) };
}

export function contextBlock(text) {
  return { type: "context", elements: [{ type: "mrkdwn", text }] };
}

export function dividerBlock() {
  return { type: "divider" };
}

// Render a fixed-width table for use inside a Slack code fence. `aligns` takes
// one "l"/"r" per column; numeric columns read best right-aligned.
export function monoTable(headers, rows, aligns = []) {
  const table = [headers, ...rows].map((row) => row.map((cell) => String(cell ?? "")));
  const widths = headers.map((_, column) =>
    Math.max(...table.map((row) => row[column].length)),
  );
  return table
    .map((row) =>
      row
        .map((cell, column) =>
          (aligns[column] === "r" ? cell.padStart(widths[column]) : cell.padEnd(widths[column])),
        )
        .join("  ")
        .trimEnd(),
    )
    .join("\n");
}
