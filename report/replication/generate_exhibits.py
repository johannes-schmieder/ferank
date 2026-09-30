#!/usr/bin/env python3
"""Generate disclosure-safe, vector exhibits for the ferank technical report.

The script reads the public LeaveOutKSS teaching extract and the two Stata
result files produced by ``run_veneto.do``.  Raw pseudonymous identifiers are
never printed in a table or figure.  The only persistent outputs are aggregate
tables and vector PDF graphics.
"""

from __future__ import annotations

import argparse
import csv
import math
import random
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from statistics import mean, median

from reportlab.lib import colors
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfgen import canvas


PAGE_W = 6.45 * 72
PAGE_H = 4.10 * 72
INK = colors.HexColor("#243447")
MUTED = colors.HexColor("#6B7C8F")
GRID = colors.HexColor("#DCE3E8")
BLUE = colors.HexColor("#2F6B9A")
ORANGE = colors.HexColor("#D77A2B")
TEAL = colors.HexColor("#2A8C82")
RED = colors.HexColor("#B94A48")


@dataclass(frozen=True)
class Observation:
    worker: int
    firm: int
    year: int
    outcome: float


def read_observations(path: Path) -> list[Observation]:
    observations: list[Observation] = []
    with path.open(newline="") as handle:
        for row in csv.reader(handle):
            if not row:
                continue
            observations.append(
                Observation(int(row[0]), int(row[1]), int(row[2]), float(row[3]))
            )
    return observations


def read_results(path: Path) -> dict[int, dict[str, float | str]]:
    rows: dict[int, dict[str, float | str]] = {}
    with path.open(newline="") as handle:
        for row in csv.DictReader(handle):
            parsed: dict[str, float | str] = {}
            for key, value in row.items():
                if key in {"method"}:
                    parsed[key] = value
                else:
                    parsed[key] = float(value) if value not in {"", None} else math.nan
            rows[int(float(row["firm_id"]))] = parsed
    return rows


def read_diagnostics(path: Path) -> dict[str, dict[str, float]]:
    diagnostics: dict[str, dict[str, float]] = {}
    with path.open(newline="") as handle:
        for row in csv.DictReader(handle):
            diagnostics[row["method"]] = {
                key: (float(value) if value not in {"", None} else math.nan)
                for key, value in row.items()
                if key != "method"
            }
    return diagnostics


def sample_sd(values: list[float]) -> float:
    center = mean(values)
    return math.sqrt(sum((value - center) ** 2 for value in values) / (len(values) - 1))


def pearson(left: list[float], right: list[float]) -> float:
    left_center = mean(left)
    right_center = mean(right)
    numerator = sum(
        (a - left_center) * (b - right_center) for a, b in zip(left, right)
    )
    denominator = math.sqrt(
        sum((a - left_center) ** 2 for a in left)
        * sum((b - right_center) ** 2 for b in right)
    )
    return numerator / denominator


def average_ranks(values: list[float]) -> list[float]:
    order = sorted(range(len(values)), key=values.__getitem__)
    ranks = [0.0] * len(values)
    cursor = 0
    while cursor < len(order):
        stop = cursor + 1
        while stop < len(order) and values[order[stop]] == values[order[cursor]]:
            stop += 1
        rank = (cursor + 1 + stop) / 2
        for index in order[cursor:stop]:
            ranks[index] = rank
        cursor = stop
    return ranks


def spearman(left: list[float], right: list[float]) -> float:
    return pearson(average_ranks(left), average_ranks(right))


def percentile(values: list[float], probability: float) -> float:
    ordered = sorted(values)
    position = probability * (len(ordered) - 1)
    lower = int(math.floor(position))
    upper = int(math.ceil(position))
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def fmt_int(value: float | int) -> str:
    return f"{int(round(value)):,}"


def fmt_float(value: float, digits: int = 3) -> str:
    return f"{value:.{digits}f}"


def latex_escape(text: str) -> str:
    replacements = {
        "&": r"\&",
        "%": r"\%",
        "_": r"\_",
        "#": r"\#",
    }
    for original, replacement in replacements.items():
        text = text.replace(original, replacement)
    return text


def build_transitions(
    observations: list[Observation], maxgap: int = 2
) -> tuple[list[tuple[int, int, int, float]], int, int]:
    by_worker: dict[int, list[Observation]] = defaultdict(list)
    for observation in observations:
        by_worker[observation.worker].append(observation)
    transitions: list[tuple[int, int, int, float]] = []
    gaps = 0
    same = 0
    for history in by_worker.values():
        history.sort(key=lambda item: item.year)
        for origin, destination in zip(history, history[1:]):
            gap = destination.year - origin.year
            if gap <= 0 or gap > maxgap:
                gaps += 1
                continue
            if origin.firm == destination.firm:
                same += 1
            transitions.append(
                (origin.firm, destination.firm, origin.worker, destination.outcome - origin.outcome)
            )
    return transitions, gaps, same


def pcg_akm(
    transitions: list[tuple[int, int, int, float]], selected: set[int], strength: Counter[int]
) -> tuple[dict[int, float], float, float, int, int, int]:
    """Fit dy = period effect + destination FE - origin FE by sparse PCG."""
    firms = sorted(selected)
    reference = max(firms, key=lambda firm: (strength[firm], -firm))
    free_firms = [firm for firm in firms if firm != reference]
    coefficient_index = {firm: index + 1 for index, firm in enumerate(free_firms)}
    rows: list[tuple[int | None, int | None, float]] = []
    stayers = 0
    for origin, destination, _worker, change in transitions:
        if origin not in selected or destination not in selected:
            continue
        if origin == destination:
            stayers += 1
        rows.append(
            (coefficient_index.get(origin), coefficient_index.get(destination), change)
        )

    dimension = len(free_firms) + 1
    rhs = [0.0] * dimension
    diagonal = [0.0] * dimension
    for origin_index, destination_index, change in rows:
        rhs[0] += change
        diagonal[0] += 1.0
        if origin_index is not None:
            rhs[origin_index] -= change
            diagonal[origin_index] += 1.0
        if destination_index is not None:
            rhs[destination_index] += change
            diagonal[destination_index] += 1.0
        if origin_index is not None and origin_index == destination_index:
            # A same-firm row has zero firm contrast, so its two unit squares
            # and cross-product cancel exactly.
            diagonal[origin_index] -= 2.0

    def multiply(vector: list[float]) -> list[float]:
        output = [0.0] * dimension
        for origin_index, destination_index, _change in rows:
            fitted = vector[0]
            if origin_index is not None:
                fitted -= vector[origin_index]
            if destination_index is not None:
                fitted += vector[destination_index]
            output[0] += fitted
            if origin_index is not None:
                output[origin_index] -= fitted
            if destination_index is not None:
                output[destination_index] += fitted
        return output

    solution = [0.0] * dimension
    residual = rhs.copy()
    preconditioned = [
        residual[index] / diagonal[index] if diagonal[index] > 0 else residual[index]
        for index in range(dimension)
    ]
    direction = preconditioned.copy()
    rz_old = sum(a * b for a, b in zip(residual, preconditioned))
    rhs_norm = math.sqrt(sum(value * value for value in rhs)) or 1.0
    iterations = 0
    for iterations in range(1, 10001):
        product = multiply(direction)
        denominator = sum(a * b for a, b in zip(direction, product))
        if denominator <= 0:
            raise RuntimeError("AKM benchmark normal equations are not positive definite")
        step = rz_old / denominator
        solution = [a + step * b for a, b in zip(solution, direction)]
        residual = [a - step * b for a, b in zip(residual, product)]
        if math.sqrt(sum(value * value for value in residual)) / rhs_norm < 1e-11:
            break
        preconditioned = [
            residual[index] / diagonal[index] if diagonal[index] > 0 else residual[index]
            for index in range(dimension)
        ]
        rz_new = sum(a * b for a, b in zip(residual, preconditioned))
        beta = rz_new / rz_old
        direction = [a + beta * b for a, b in zip(preconditioned, direction)]
        rz_old = rz_new
    else:
        raise RuntimeError("AKM benchmark PCG did not converge")

    effects = {reference: 0.0}
    effects.update({firm: solution[index] for firm, index in coefficient_index.items()})
    effect_mean = mean(list(effects.values()))
    effects = {firm: value - effect_mean for firm, value in effects.items()}
    selected_outcomes = [change for _origin, _destination, change in rows]
    fitted_values: list[float] = []
    for origin_index, destination_index, _change in rows:
        fitted = solution[0]
        if origin_index is not None:
            fitted -= solution[origin_index]
        if destination_index is not None:
            fitted += solution[destination_index]
        fitted_values.append(fitted)
    selected_mean = mean(selected_outcomes)
    total_ss = sum((value - selected_mean) ** 2 for value in selected_outcomes)
    residual_ss = sum(
        (value - fitted) ** 2 for value, fitted in zip(selected_outcomes, fitted_values)
    )
    r_squared = 1 - residual_ss / total_ss
    movers = len(rows) - stayers
    return effects, solution[0], r_squared, len(rows), movers, iterations


def prepare_canvas(path: Path, title: str, subtitle: str | None = None) -> canvas.Canvas:
    drawing = canvas.Canvas(str(path), pagesize=(PAGE_W, PAGE_H), invariant=1)
    drawing.setTitle(title)
    drawing.setFillColor(INK)
    drawing.setFont("Helvetica-Bold", 12)
    drawing.drawString(36, PAGE_H - 25, title)
    if subtitle:
        drawing.setFillColor(MUTED)
        drawing.setFont("Helvetica", 7.6)
        drawing.drawString(36, PAGE_H - 37, subtitle)
    return drawing


def draw_arrow(
    drawing: canvas.Canvas,
    x1: float,
    y1: float,
    x2: float,
    y2: float,
    color: colors.Color = BLUE,
    width: float = 1.2,
    head: float = 5.0,
) -> None:
    angle = math.atan2(y2 - y1, x2 - x1)
    drawing.setStrokeColor(color)
    drawing.setFillColor(color)
    drawing.setLineWidth(width)
    drawing.line(x1, y1, x2, y2)
    drawing.line(
        x2,
        y2,
        x2 - head * math.cos(angle - 0.45),
        y2 - head * math.sin(angle - 0.45),
    )
    drawing.line(
        x2,
        y2,
        x2 - head * math.cos(angle + 0.45),
        y2 - head * math.sin(angle + 0.45),
    )


def graph_concepts_figure(path: Path) -> None:
    drawing = prepare_canvas(
        path,
        "Reading a worker-flow graph",
        "Circles are firms; an arrow records at least one observed worker move in that direction.",
    )
    panels = [43, 189, 335]
    titles = ["1. Directed edge", "2. Directed path", "3. Strong connectivity"]
    captions = [
        "A mover goes from A to B.",
        "A reaches C through B.",
        "Every pair can reach each other.",
    ]
    for left, title, caption in zip(panels, titles, captions):
        drawing.setFillColor(INK)
        drawing.setFont("Helvetica-Bold", 8.5)
        drawing.drawString(left, PAGE_H - 61, title)
        drawing.setFillColor(MUTED)
        drawing.setFont("Helvetica", 7)
        drawing.drawString(left, 31, caption)
    node_y = 142

    def node(x: float, y: float, label: str, fill: colors.Color = colors.white) -> None:
        drawing.setFillColor(fill)
        drawing.setStrokeColor(INK)
        drawing.setLineWidth(1.1)
        drawing.circle(x, y, 14, stroke=1, fill=1)
        drawing.setFillColor(INK)
        drawing.setFont("Helvetica-Bold", 8)
        drawing.drawCentredString(x, y - 3, label)

    node(74, node_y, "A")
    node(145, node_y, "B")
    draw_arrow(drawing, 90, node_y, 128, node_y)
    drawing.setFillColor(BLUE)
    drawing.setFont("Helvetica", 7)
    drawing.drawCentredString(109, node_y + 11, "worker move")

    node(210, node_y, "A")
    node(261, node_y, "B")
    node(312, node_y, "C")
    draw_arrow(drawing, 226, node_y, 244, node_y)
    draw_arrow(drawing, 277, node_y, 295, node_y)
    drawing.setStrokeColor(ORANGE)
    drawing.setDash(3, 2)
    drawing.setLineWidth(1)
    drawing.line(210, 105, 312, 105)
    drawing.setDash()
    drawing.setFillColor(ORANGE)
    drawing.setFont("Helvetica", 7)
    drawing.drawCentredString(261, 94, "path A -> B -> C")

    node(367, node_y + 20, "A", colors.HexColor("#E9F3F6"))
    node(422, node_y - 17, "B", colors.HexColor("#E9F3F6"))
    node(443, node_y + 40, "C", colors.HexColor("#E9F3F6"))
    draw_arrow(drawing, 381, node_y + 11, 407, node_y - 8, TEAL)
    draw_arrow(drawing, 411, node_y - 1, 383, node_y + 14, TEAL)
    draw_arrow(drawing, 427, node_y - 1, 438, node_y + 23, TEAL)
    draw_arrow(drawing, 431, node_y + 33, 383, node_y + 24, TEAL)
    drawing.setFillColor(TEAL)
    drawing.setFont("Helvetica", 7)
    drawing.drawCentredString(394, 88, "one strongly connected component")
    drawing.save()


def interpolate_color(value: float) -> colors.Color:
    value = max(0.0, min(1.0, value))
    low = (47 / 255, 107 / 255, 154 / 255)
    high = (215 / 255, 122 / 255, 43 / 255)
    return colors.Color(*(low[index] * (1 - value) + high[index] * value for index in range(3)))


def force_layout(
    nodes: list[int], undirected: Counter[tuple[int, int]], seed: int = 9841
) -> dict[int, tuple[float, float]]:
    randomizer = random.Random(seed)
    positions = {
        node: (randomizer.uniform(-1, 1), randomizer.uniform(-1, 1)) for node in nodes
    }
    area = 4.0
    ideal = math.sqrt(area / len(nodes))
    max_weight = max(undirected.values()) if undirected else 1
    for iteration in range(500):
        displacement = {node: [0.0, 0.0] for node in nodes}
        for offset, left in enumerate(nodes):
            for right in nodes[offset + 1 :]:
                dx = positions[left][0] - positions[right][0]
                dy = positions[left][1] - positions[right][1]
                distance = max(0.025, math.hypot(dx, dy))
                force = ideal * ideal / distance
                ux, uy = dx / distance, dy / distance
                displacement[left][0] += ux * force
                displacement[left][1] += uy * force
                displacement[right][0] -= ux * force
                displacement[right][1] -= uy * force
        for (left, right), weight in undirected.items():
            if left not in positions or right not in positions:
                continue
            dx = positions[left][0] - positions[right][0]
            dy = positions[left][1] - positions[right][1]
            distance = max(0.025, math.hypot(dx, dy))
            force = distance * distance / ideal * (0.45 + 0.55 * math.sqrt(weight / max_weight))
            ux, uy = dx / distance, dy / distance
            displacement[left][0] -= ux * force
            displacement[left][1] -= uy * force
            displacement[right][0] += ux * force
            displacement[right][1] += uy * force
        temperature = 0.12 * (1 - iteration / 500) + 0.004
        next_positions = {}
        for node in nodes:
            dx, dy = displacement[node]
            distance = max(1e-12, math.hypot(dx, dy))
            next_positions[node] = (
                positions[node][0] + dx / distance * min(distance, temperature),
                positions[node][1] + dy / distance * min(distance, temperature),
            )
        positions = next_positions
    return positions


def network_figure(
    path: Path,
    edge_counts: Counter[tuple[int, int]],
    selected: set[int],
    scores: dict[int, float],
    strength: Counter[int],
) -> tuple[int, int]:
    undirected_all: Counter[tuple[int, int]] = Counter()
    neighbors: dict[int, Counter[int]] = defaultdict(Counter)
    for (origin, destination), count in edge_counts.items():
        if origin not in selected or destination not in selected:
            continue
        pair = tuple(sorted((origin, destination)))
        undirected_all[pair] += count
        neighbors[origin][destination] += count
        neighbors[destination][origin] += count
    seed = max(selected, key=lambda firm: (strength[firm], -firm))
    core = {seed}
    while len(core) < 24:
        candidates: Counter[int] = Counter()
        for firm in core:
            for neighbor, count in neighbors[firm].items():
                if neighbor not in core:
                    candidates[neighbor] += count
        if candidates:
            core.add(max(candidates, key=lambda firm: (candidates[firm], strength[firm], -firm)))
        else:
            core.add(max(selected - core, key=lambda firm: (strength[firm], -firm)))
    nodes = sorted(core, key=lambda firm: (-strength[firm], firm))
    aliases = {firm: f"F{index:02d}" for index, firm in enumerate(nodes, start=1)}
    induced = Counter(
        {
            pair: count
            for pair, count in undirected_all.items()
            if pair[0] in core and pair[1] in core
        }
    )
    positions = force_layout(nodes, induced)
    x_values = [positions[node][0] for node in nodes]
    y_values = [positions[node][1] for node in nodes]
    x_min, x_max = min(x_values), max(x_values)
    y_min, y_max = min(y_values), max(y_values)
    plot_left, plot_right = 42, PAGE_W - 42
    plot_bottom, plot_top = 43, PAGE_H - 50

    def map_position(node: int) -> tuple[float, float]:
        x, y = positions[node]
        return (
            plot_left + (x - x_min) / (x_max - x_min) * (plot_right - plot_left),
            plot_bottom + (y - y_min) / (y_max - y_min) * (plot_top - plot_bottom),
        )

    drawing = prepare_canvas(
        path,
        "A high-flow core of the Veneto mobility network",
        "Actual 1999-2001 moves; 24 firms selected recursively by strongest connection. Plot labels replace pseudonymous IDs.",
    )
    directed = [
        (origin, destination, count)
        for (origin, destination), count in edge_counts.items()
        if origin in core and destination in core
    ]
    directed.sort(key=lambda item: item[2], reverse=True)
    displayed_edges = directed[:55]
    max_edge = max(count for _origin, _destination, count in displayed_edges)
    for origin, destination, count in reversed(displayed_edges):
        x1, y1 = map_position(origin)
        x2, y2 = map_position(destination)
        dx, dy = x2 - x1, y2 - y1
        distance = max(1.0, math.hypot(dx, dy))
        origin_radius = 5.0 + 3.1 * math.sqrt(strength[origin] / max(strength.values()))
        destination_radius = 5.0 + 3.1 * math.sqrt(strength[destination] / max(strength.values()))
        x1 += dx / distance * origin_radius
        y1 += dy / distance * origin_radius
        x2 -= dx / distance * (destination_radius + 2.5)
        y2 -= dy / distance * (destination_radius + 2.5)
        drawing.saveState()
        if hasattr(drawing, "setStrokeAlpha"):
            drawing.setStrokeAlpha(0.30 + 0.45 * math.sqrt(count / max_edge))
        draw_arrow(
            drawing,
            x1,
            y1,
            x2,
            y2,
            color=colors.HexColor("#71879A"),
            width=0.35 + 1.45 * math.sqrt(count / max_edge),
            head=3.2,
        )
        drawing.restoreState()
    score_values = [scores[node] for node in nodes]
    score_low = percentile(score_values, 0.05)
    score_high = percentile(score_values, 0.95)
    maximum_strength = max(strength[node] for node in nodes)
    for node in reversed(nodes):
        x, y = map_position(node)
        radius = 6.0 + 4.3 * math.sqrt(strength[node] / maximum_strength)
        color_value = (scores[node] - score_low) / max(1e-12, score_high - score_low)
        drawing.setFillColor(interpolate_color(color_value))
        drawing.setStrokeColor(colors.white)
        drawing.setLineWidth(0.9)
        drawing.circle(x, y, radius, stroke=1, fill=1)
        drawing.setFillColor(colors.white)
        drawing.setFont("Helvetica-Bold", 5.6)
        drawing.drawCentredString(x, y - 2, aliases[node])
    drawing.setFillColor(MUTED)
    drawing.setFont("Helvetica", 6.5)
    drawing.drawRightString(PAGE_W - 36, 22, "blue = lower Sorkin score     orange = higher Sorkin score")
    drawing.save()
    return len(core), len(displayed_edges)


def axes(
    drawing: canvas.Canvas,
    box: tuple[float, float, float, float],
    x_label: str,
    y_label: str,
    x_ticks: list[float],
    y_ticks: list[float],
    x_range: tuple[float, float],
    y_range: tuple[float, float],
) -> tuple[callable, callable]:
    left, bottom, right, top = box

    def map_x(value: float) -> float:
        return left + (value - x_range[0]) / (x_range[1] - x_range[0]) * (right - left)

    def map_y(value: float) -> float:
        return bottom + (value - y_range[0]) / (y_range[1] - y_range[0]) * (top - bottom)

    drawing.setFont("Helvetica", 6.5)
    for tick in x_ticks:
        position = map_x(tick)
        drawing.setStrokeColor(GRID)
        drawing.setLineWidth(0.5)
        drawing.line(position, bottom, position, top)
        drawing.setFillColor(MUTED)
        drawing.drawCentredString(position, bottom - 11, f"{tick:g}")
    for tick in y_ticks:
        position = map_y(tick)
        drawing.setStrokeColor(GRID)
        drawing.line(left, position, right, position)
        drawing.setFillColor(MUTED)
        drawing.drawRightString(left - 5, position - 2, f"{tick:g}")
    drawing.setStrokeColor(INK)
    drawing.setLineWidth(0.8)
    drawing.rect(left, bottom, right - left, top - bottom, stroke=1, fill=0)
    drawing.setFillColor(INK)
    drawing.setFont("Helvetica", 7)
    drawing.drawCentredString((left + right) / 2, bottom - 24, x_label)
    drawing.saveState()
    drawing.translate(left - 31, (bottom + top) / 2)
    drawing.rotate(90)
    drawing.drawCentredString(0, 0, y_label)
    drawing.restoreState()
    return map_x, map_y


def rank_comparison_figure(
    path: Path, sorkin: dict[int, dict[str, float | str]], bt: dict[int, dict[str, float | str]]
) -> None:
    firms = sorted(set(sorkin) & set(bt))
    x_values = [float(sorkin[firm]["percentile"]) for firm in firms]
    y_values = [float(bt[firm]["percentile"]) for firm in firms]
    rho = spearman(x_values, y_values)
    drawing = prepare_canvas(
        path,
        "The two flow estimators agree, but not mechanically",
        f"Each point is one of {len(firms):,} firms in the largest strongly connected component; Spearman rho = {rho:.3f}.",
    )
    map_x, map_y = axes(
        drawing,
        (55, 45, PAGE_W - 38, PAGE_H - 53),
        "Sorkin rank percentile",
        "Bradley-Terry rank percentile",
        [0, 25, 50, 75, 100],
        [0, 25, 50, 75, 100],
        (0, 100),
        (0, 100),
    )
    drawing.setStrokeColor(ORANGE)
    drawing.setDash(4, 3)
    drawing.setLineWidth(1)
    drawing.line(map_x(0), map_y(0), map_x(100), map_y(100))
    drawing.setDash()
    drawing.saveState()
    if hasattr(drawing, "setFillAlpha"):
        drawing.setFillAlpha(0.42)
    drawing.setFillColor(BLUE)
    for x_value, y_value in zip(x_values, y_values):
        drawing.circle(map_x(x_value), map_y(y_value), 1.45, stroke=0, fill=1)
    drawing.restoreState()
    drawing.save()


def akm_comparison_figure(
    path: Path,
    effects: dict[int, float],
    sorkin: dict[int, dict[str, float | str]],
    bt: dict[int, dict[str, float | str]],
) -> None:
    firms = sorted(effects)
    effect_values = [effects[firm] for firm in firms]
    effect_sd = sample_sd(effect_values)
    standardized = [value / effect_sd for value in effect_values]
    x_low = math.floor(percentile(standardized, 0.01) * 2) / 2
    x_high = math.ceil(percentile(standardized, 0.99) * 2) / 2
    drawing = prepare_canvas(
        path,
        "Worker-flow rankings and a two-period AKM-style benchmark",
        "The benchmark fits the change in the supplied outcome to a common 1999-2001 change and origin/destination firm effects.",
    )
    panels = [
        (55, 49, 231, PAGE_H - 56, "Sorkin", sorkin, BLUE),
        (286, 49, PAGE_W - 34, PAGE_H - 56, "Bradley-Terry", bt, ORANGE),
    ]
    for left, bottom, right, top, title, results, color in panels:
        map_x, map_y = axes(
            drawing,
            (left, bottom, right, top),
            "AKM-style firm effect (SD)",
            "flow rank percentile",
            [x_low, 0, x_high],
            [0, 25, 50, 75, 100],
            (x_low, x_high),
            (0, 100),
        )
        rank_values = [float(results[firm]["percentile"]) for firm in firms]
        rho = spearman(effect_values, rank_values)
        drawing.setFillColor(INK)
        drawing.setFont("Helvetica-Bold", 7.5)
        drawing.drawCentredString((left + right) / 2, top + 7, f"{title}: rho = {rho:.3f}")
        drawing.saveState()
        if hasattr(drawing, "setFillAlpha"):
            drawing.setFillAlpha(0.42)
        drawing.setFillColor(color)
        for effect, rank_value in zip(standardized, rank_values):
            clipped = max(x_low, min(x_high, effect))
            drawing.circle(map_x(clipped), map_y(rank_value), 1.25, stroke=0, fill=1)
        drawing.restoreState()
    drawing.save()


def write_table(path: Path, contents: str) -> None:
    path.write_text(contents.strip() + "\n")


def generate_tables(
    generated: Path,
    observations: list[Observation],
    transitions: list[tuple[int, int, int, float]],
    edge_counts: Counter[tuple[int, int]],
    sorkin: dict[int, dict[str, float | str]],
    bt: dict[int, dict[str, float | str]],
    diagnostics: dict[str, dict[str, float]],
    effects: dict[int, float],
    period_effect: float,
    akm_r_squared: float,
    akm_rows: int,
    akm_movers: int,
    akm_iterations: int,
    network_nodes: int,
    network_edges: int,
) -> None:
    workers = {observation.worker for observation in observations}
    raw_firms = {observation.firm for observation in observations}
    years = sorted({observation.year for observation in observations})
    changes = [change for _origin, _destination, _worker, change in transitions]
    moves = [row for row in transitions if row[0] != row[1]]
    move_firms = {firm for origin, destination, _worker, _change in moves for firm in (origin, destination)}
    selected = set(sorkin)
    selected_edges = sum(
        1 for origin, destination in edge_counts if origin in selected and destination in selected
    )
    selected_moves = sum(
        count
        for (origin, destination), count in edge_counts.items()
        if origin in selected and destination in selected
    )

    sample_rows = [
        ("Rows", fmt_int(len(observations)), "Two observations per worker"),
        ("Workers", fmt_int(len(workers)), "Pseudonymous worker identifiers"),
        ("Years", f"{years[0]} and {years[-1]}", "A two-year gap"),
        ("Firms in raw extract", fmt_int(len(raw_firms)), "Includes firms observed only among stayers"),
        ("Valid worker transitions", fmt_int(len(transitions)), "Requires maxgap(2)"),
        ("Same-firm continuations", fmt_int(sum(1 for row in transitions if row[0] == row[1])), "Not graph edges"),
        ("Worker moves", fmt_int(len(moves)), "Origin and destination differ"),
        ("Firms in mobility graph", fmt_int(len(move_firms)), "Appear in at least one move"),
        ("Distinct directed edges", fmt_int(len(edge_counts)), "Firm-pair directions with positive flow"),
        ("Strongly connected components", fmt_int(diagnostics["sorkin"]["N_components"]), "In the full directed mobility graph"),
        ("Firms in largest SCC", fmt_int(len(selected)), "Estimation sample for both methods"),
        ("Moves within largest SCC", fmt_int(selected_moves), "Used by the fitted component"),
        ("Directed edges within largest SCC", fmt_int(selected_edges), "Positive flows retained"),
    ]
    sample_body = "\n".join(
        f"{latex_escape(label)} & {value} & {latex_escape(note)} \\\\"
        for label, value, note in sample_rows
    )
    write_table(
        generated / "veneto_sample_stats.tex",
        rf"""
\begin{{tabularx}}{{\linewidth}}{{@{{}}L{{0.36\linewidth}}rX@{{}}}}
\toprule
Quantity & Value & Interpretation \\
\midrule
{sample_body}
\bottomrule
\end{{tabularx}}
""",
    )

    sdiag, bdiag = diagnostics["sorkin"], diagnostics["bradleyterry"]
    diagnostics_rows = [
        ("Iterations", fmt_int(sdiag["iterations"]), fmt_int(bdiag["iterations"])),
        ("Fixed-point max residual", f"{sdiag['residual_max']:.2e}", "--"),
        ("Fixed-point L1 residual", f"{sdiag['residual_l1']:.2e}", "--"),
        ("Log likelihood", "--", fmt_float(bdiag["log_likelihood"], 3)),
        ("Maximum score gradient", "--", f"{bdiag['gradient_max']:.2e}"),
        ("Newton-system residual", "--", f"{bdiag['newton_residual']:.2e}"),
        ("Line-search backtracks", "--", fmt_int(bdiag["line_search_steps"])),
    ]
    diagnostics_body = "\n".join(
        f"{latex_escape(label)} & {sorkin_value} & {bt_value} \\\\"
        for label, sorkin_value, bt_value in diagnostics_rows
    )
    write_table(
        generated / "estimator_diagnostics.tex",
        rf"""
\begin{{tabular}}{{@{{}}lrr@{{}}}}
\toprule
Diagnostic & Sorkin & Bradley--Terry \\
\midrule
{diagnostics_body}
\bottomrule
\end{{tabular}}
""",
    )

    firms = sorted(selected)
    s_scores = [float(sorkin[firm]["score"]) for firm in firms]
    b_scores = [float(bt[firm]["score"]) for firm in firms]
    a_scores = [effects[firm] for firm in firms]
    s_percentiles = [float(sorkin[firm]["percentile"]) for firm in firms]
    b_percentiles = [float(bt[firm]["percentile"]) for firm in firms]
    cutoff = percentile(s_scores, 0.9)
    cutoff_bt = percentile(b_scores, 0.9)
    top_s = {firm for firm in firms if float(sorkin[firm]["score"]) >= cutoff}
    top_b = {firm for firm in firms if float(bt[firm]["score"]) >= cutoff_bt}
    agreement_rows = [
        ("Sorkin vs. Bradley--Terry score", pearson(s_scores, b_scores), spearman(s_scores, b_scores)),
        ("Sorkin score vs. AKM-style effect", pearson(s_scores, a_scores), spearman(s_scores, a_scores)),
        ("Bradley--Terry score vs. AKM-style effect", pearson(b_scores, a_scores), spearman(b_scores, a_scores)),
    ]
    agreement_body = "\n".join(
        f"{label} & {linear:.3f} & {ranked:.3f} \\\\"
        for label, linear, ranked in agreement_rows
    )
    write_table(
        generated / "score_agreement.tex",
        rf"""
\begin{{tabularx}}{{\linewidth}}{{@{{}}Xrr@{{}}}}
\toprule
Comparison & Pearson & Spearman \\
\midrule
{agreement_body}
\addlinespace
Top-decile overlap (share of Sorkin top decile) & \multicolumn{{2}}{{r}}{{{len(top_s & top_b) / len(top_s):.3f}}} \\
\bottomrule
\end{{tabularx}}
""",
    )

    ordered = sorted(firms, key=lambda firm: float(sorkin[firm]["score"]))
    decile_rows = []
    for decile in range(10):
        lower = round(decile * len(ordered) / 10)
        upper = round((decile + 1) * len(ordered) / 10)
        group = ordered[lower:upper]
        decile_rows.append(
            (
                decile + 1,
                len(group),
                median(float(sorkin[firm]["score"]) for firm in group),
                median(float(bt[firm]["percentile"]) for firm in group),
                median(effects[firm] for firm in group),
                sum(float(sorkin[firm]["inflow"]) + float(sorkin[firm]["outflow"]) for firm in group),
            )
        )
    decile_body = "\n".join(
        f"{decile} & {count} & {score:.3f} & {bt_percentile:.1f} & {effect:.4f} & {fmt_int(flow)} \\\\"
        for decile, count, score, bt_percentile, effect, flow in decile_rows
    )
    write_table(
        generated / "sorkin_deciles.tex",
        rf"""
\begin{{tabular}}{{@{{}}rrrrrr@{{}}}}
\toprule
Sorkin decile & Firms & Median score & Median BT pct. & Median AKM effect & Total flow \\
\midrule
{decile_body}
\bottomrule
\end{{tabular}}
""",
    )

    command_rows = [
        (r"\texttt{e(N\_input)}", "71,614", "Input rows after markout"),
        (r"\texttt{e(N\_firms)}", "3,630", "Firms in the informative mobility graph"),
        (r"\texttt{e(N\_results)}", "702", "Firms returned after component selection"),
        (r"\texttt{e(N\_edges)}", "6,043", "Canonical directed edges before selection"),
        (r"\texttt{e(N\_components)}", "2,917", "Strongly connected components"),
        (r"\texttt{e(valid\_moves)}", "8,243", "Cross-firm transitions"),
        (r"\texttt{e(same\_firm\_continuations)}", "27,564", "Valid adjacent records without a move"),
        (r"\texttt{e(method)}", "method name", "Estimator actually run"),
        (r"\texttt{e(component)}", "largest", "Component rule actually applied"),
        (r"\texttt{e(normalize)}", "mean", "Score normalization"),
    ]
    command_body = "\n".join(
        f"{name} & {value} & {description} \\\\"
        for name, value, description in command_rows
    )
    write_table(
        generated / "returned_results.tex",
        rf"""
\begin{{tabularx}}{{\linewidth}}{{@{{}}lR{{0.18\linewidth}}X@{{}}}}
\toprule
Returned result & Veneto value & Meaning \\
\midrule
{command_body}
\bottomrule
\end{{tabularx}}
""",
    )

    macro_values = {
        "VenetoRows": fmt_int(len(observations)),
        "VenetoWorkers": fmt_int(len(workers)),
        "VenetoRawFirms": fmt_int(len(raw_firms)),
        "VenetoMoves": fmt_int(len(moves)),
        "VenetoSameFirm": fmt_int(sum(1 for row in transitions if row[0] == row[1])),
        "VenetoEdges": fmt_int(len(edge_counts)),
        "VenetoGraphFirms": fmt_int(len(move_firms)),
        "VenetoLargestSCC": fmt_int(len(selected)),
        "VenetoSelectedMoves": fmt_int(selected_moves),
        "VenetoSelectedEdges": fmt_int(selected_edges),
        "VenetoMeanChange": fmt_float(mean(changes), 4),
        "VenetoSDChange": fmt_float(sample_sd(changes), 4),
        "AkmRows": fmt_int(akm_rows),
        "AkmMovers": fmt_int(akm_movers),
        "AkmPeriodEffect": fmt_float(period_effect, 4),
        "AkmRSquared": fmt_float(akm_r_squared, 3),
        "AkmIterations": fmt_int(akm_iterations),
        "NetworkNodes": fmt_int(network_nodes),
        "NetworkEdges": fmt_int(network_edges),
        "SorkinBtSpearman": fmt_float(spearman(s_percentiles, b_percentiles), 3),
        "SorkinAkmSpearman": fmt_float(spearman(s_scores, a_scores), 3),
        "BtAkmSpearman": fmt_float(spearman(b_scores, a_scores), 3),
    }
    write_table(
        generated / "report_values.tex",
        "\n".join(
            rf"\newcommand{{\{name}}}{{{value}}}" for name, value in macro_values.items()
        ),
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--results", type=Path, required=True)
    parser.add_argument("--generated", type=Path, required=True)
    arguments = parser.parse_args()
    arguments.generated.mkdir(parents=True, exist_ok=True)

    observations = read_observations(arguments.data)
    transitions, gap_breaks, _same = build_transitions(observations)
    if gap_breaks:
        raise RuntimeError(f"unexpected gap breaks with maxgap(2): {gap_breaks}")
    edge_counts = Counter(
        (origin, destination)
        for origin, destination, _worker, _change in transitions
        if origin != destination
    )
    sorkin = read_results(arguments.results / "sorkin.csv")
    bt = read_results(arguments.results / "bradleyterry.csv")
    diagnostics = read_diagnostics(arguments.results / "diagnostics.csv")
    if set(sorkin) != set(bt):
        raise RuntimeError("Sorkin and Bradley-Terry result firm sets differ")
    selected = set(sorkin)
    strength: Counter[int] = Counter()
    for (origin, destination), count in edge_counts.items():
        if origin in selected and destination in selected:
            strength[origin] += count
            strength[destination] += count

    effects, period_effect, r_squared, akm_rows, akm_movers, akm_iterations = pcg_akm(
        transitions, selected, strength
    )
    graph_concepts_figure(arguments.generated / "graph_concepts.pdf")
    network_nodes, network_edges = network_figure(
        arguments.generated / "veneto_network.pdf",
        edge_counts,
        selected,
        {firm: float(row["score"]) for firm, row in sorkin.items()},
        strength,
    )
    rank_comparison_figure(arguments.generated / "rank_comparison.pdf", sorkin, bt)
    akm_comparison_figure(
        arguments.generated / "akm_comparison.pdf", effects, sorkin, bt
    )
    generate_tables(
        arguments.generated,
        observations,
        transitions,
        edge_counts,
        sorkin,
        bt,
        diagnostics,
        effects,
        period_effect,
        r_squared,
        akm_rows,
        akm_movers,
        akm_iterations,
        network_nodes,
        network_edges,
    )
    print(
        f"generated report exhibits for {len(selected):,} firms; "
        f"AKM benchmark used {akm_rows:,} transitions and converged in {akm_iterations:,} iterations"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
