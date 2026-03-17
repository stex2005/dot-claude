---
description: Create a draw.io XML diagram from code, architecture, or a user description
allowed-tools: Bash(ls:*), Bash(find:*), Bash(drawio:*), Bash(xdg-open:*), Read, Write, Glob, Grep, Agent
---

## Context

- Current directory: !`pwd`
- Files in current directory: !`ls`

## Your task

Create a draw.io-compatible XML diagram (`.drawio` file) based on the user's request.

### Steps

1. Understand what the user wants to diagram. If unclear, ask. Common types:
   - Architecture / system diagrams
   - Sequence diagrams
   - Class / entity-relationship diagrams
   - Flow charts / decision trees
   - Component or dependency graphs
2. If the diagram is based on code, read the relevant source files to extract the structure.
3. Generate a valid draw.io XML diagram (`mxGraphModel` format).
4. Ask the user for the output file name and location, suggesting a sensible default (e.g., `docs/diagram.drawio` or `<name>.drawio` in the repo root).
5. Write the `.drawio` file.
6. Show the user a brief summary of what the diagram contains (nodes, connections, layout).
7. If the user asks to open the diagram, run `drawio <file>` (or `xdg-open <file>` as fallback). Do NOT open automatically.

### Draw.io XML rules

- CRITICAL: `<mxfile>` MUST have `host="app.diagrams.net"` attribute.
- CRITICAL: Every edge MUST have a child `<mxGeometry relative="1" as="geometry" />` element.
- CRITICAL: Use self-closing tags for `<mxCell ... />` and `<mxGeometry ... />` when they have no children.
- Use `&#xa;` for newlines inside `value` labels (not `<br>`).
- Use the standard draw.io XML structure:
  ```xml
  <mxfile host="app.diagrams.net" type="device">
    <diagram id="unique-id" name="Diagram Name">
      <mxGraphModel dx="1200" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1100" pageHeight="850" math="0" shadow="0">
        <root>
          <mxCell id="0" />
          <mxCell id="1" parent="0" />
          <!-- vertex (shape) example -->
          <mxCell id="2" value="Label" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
            <mxGeometry x="100" y="100" width="120" height="40" as="geometry" />
          </mxCell>
          <!-- edge example -->
          <mxCell id="e1" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="2" target="3" parent="1">
            <mxGeometry relative="1" as="geometry" />
          </mxCell>
        </root>
      </mxGraphModel>
    </diagram>
  </mxfile>
  ```
- Assign unique `id` attributes to every `mxCell`.
- Use `parent="1"` for top-level shapes.
- For edges, set `edge="1"`, `source`, and `target` attributes.
- Apply sensible geometry: avoid overlapping nodes, use a grid-aligned layout.
- Set `pageHeight` large enough to fit the diagram (e.g., 1200+ for tall flowcharts).
- Use appropriate styles for different element types (e.g., `rounded=1` for services, `shape=cylinder3` for databases, `rhombus` for decisions).
- Use meaningful labels on all nodes and edges.
- Keep the layout clean: consistent spacing, logical flow direction (top-to-bottom or left-to-right).

### Rules

- Always produce valid draw.io XML that can be opened in draw.io or diagrams.net without errors.
- Do NOT produce ASCII art, Mermaid, or PlantUML -- only draw.io XML.
- If the diagram would be too large or complex, ask the user if they want to split it into multiple diagrams or simplify.
