---
description: Create a draw.io software architecture diagram from code or a description
allowed-tools: Bash(ls:*), Bash(find:*), Bash(drawio:*), Bash(xdg-open:*), Read, Write, Glob, Grep, Agent
---

## Context

- Current directory: !`pwd`
- Files in current directory: !`ls`
- Git repo root: !`git rev-parse --show-toplevel 2>/dev/null || echo "not a git repo"`

## Your task

Create a draw.io-compatible software architecture diagram (`.drawio` file) based on the user's request.

### Steps

1. Understand what the user wants to diagram. If unclear, ask. Common types:
   - System / high-level architecture (services, databases, queues, external APIs)
   - Component diagrams (modules, packages, layers)
   - Deployment diagrams (containers, hosts, cloud services)
   - Data flow diagrams (how data moves through the system)
   - Class / module dependency graphs
   - Sequence or interaction diagrams between services
2. Read the relevant source files, configs, docker-compose files, CI/CD configs, or infrastructure code to extract the architecture.
3. Generate a valid draw.io XML diagram.
4. Ask the user for the output file name and location, suggesting a sensible default (e.g., `docs/architecture.drawio`).
5. Write the `.drawio` file.
6. Show the user a brief summary of what the diagram contains (components, connections, layers).
7. If the user asks to open the diagram, run `drawio <file>` (or `xdg-open <file>` as fallback). Do NOT open automatically.

### Diagram conventions

- **Services / applications**: Rounded rectangles (`rounded=1`), blue fill (`#dae8fc`).
- **Databases**: Cylinder shape (`shape=cylinder3`), orange fill (`#fff2cc`).
- **Message queues / event buses**: Parallelogram or hexagon, purple fill (`#e1d5e7`).
- **External APIs / third-party services**: Dashed border (`dashed=1`), gray fill (`#f5f5f5`).
- **Users / clients**: Person shape or cloud shape at the top/left of the diagram.
- **Load balancers / gateways**: Trapezoid or rounded rectangle with distinct style.
- **Containers / boundaries**: Use grouping rectangles (`container=1`) with a label to represent deployment boundaries (e.g., VPC, Kubernetes cluster, Docker host). Light background fill, no stroke or dashed stroke.
- **Layers**: If the architecture has layers (presentation, business logic, data), arrange top-to-bottom with horizontal separator groups.
- **Connections**: Label every edge with the protocol or interaction type (e.g., `HTTP/REST`, `gRPC`, `SQL`, `pub/sub`, `WebSocket`).
- **Arrow styles**: Solid for synchronous, dashed for asynchronous.
- **Flow direction**: Left-to-right or top-to-bottom. Users/clients at the top or left, data stores at the bottom or right.
- **Color coding**:
  - Blue `#dae8fc` — application services
  - Green `#d5e8d4` — infrastructure / platform services
  - Orange `#fff2cc` — data stores
  - Purple `#e1d5e7` — messaging / event systems
  - Red `#f8cecc` — external / third-party
  - Gray `#f5f5f5` — boundaries / groups

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
          <!-- shapes and edges here -->
        </root>
      </mxGraphModel>
    </diagram>
  </mxfile>
  ```
- Assign unique `id` attributes to every `mxCell`.
- Use `parent="1"` for top-level shapes (or parent of a group cell for grouped elements).
- For edges, set `edge="1"`, `source`, and `target` attributes.
- Apply sensible geometry: avoid overlapping nodes, use a grid-aligned layout.
- Set `pageHeight` and `pageWidth` large enough to fit the diagram.

### Rules

- Always produce valid draw.io XML that can be opened in draw.io or diagrams.net without errors.
- Do NOT produce ASCII art, Mermaid, or PlantUML -- only draw.io XML.
- If the diagram would be too large or complex, ask the user if they want to split it into multiple diagrams or simplify.
- Prefer extracting the real architecture from code over asking the user to describe it. Read configs, imports, docker-compose, Terraform, etc.
