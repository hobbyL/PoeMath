import 'dart:ffi';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:pdfium_dart/pdfium_dart.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_page_layout.dart';

const _identity = <double>[1, 0, 0, 1, 0, 0];
const _maxObjects = 12000;
const _maxSegments = 100000;
const _maxFormDepth = 16;

List<double> _compose(List<double> p, List<double> c) => [
  p[0] * c[0] + p[2] * c[1],
  p[1] * c[0] + p[3] * c[1],
  p[0] * c[2] + p[2] * c[3],
  p[1] * c[2] + p[3] * c[3],
  p[0] * c[4] + p[2] * c[5] + p[4],
  p[1] * c[4] + p[3] * c[5] + p[5],
];

(double, double) _transform(List<double> m, double x, double y) =>
    (m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]);

/// 调用方必须在 PdfDocument.useNativeDocumentHandle 的同步回调内执行。
/// 不初始化/销毁 PDFium，不持有 documentHandle，不调用异步 worker。
MathTextbookGraphics readMathTextbookGraphics(
  int documentHandle,
  int pageNumber, {
  String? modulePath,
}) {
  final api = getPdfium(modulePath: modulePath);
  final document = FPDF_DOCUMENT.fromAddress(documentHandle);
  final page = api.FPDF_LoadPage(document, pageNumber - 1);
  if (page.address == 0) throw const FormatException('数学原书页面无法读取');
  try {
    return using((arena) {
      final bounds = arena<FS_RECTF>();
      final matrix = arena<FS_MATRIX>();
      final coords = arena<Float>(4);
      final modes = arena<Int>(2);
      final color = arena<UnsignedInt>(4);
      if (api.FPDF_GetPageBoundingBox(page, bounds) == 0) {
        throw const FormatException('数学原书页面边界无法读取');
      }
      final box = bounds.ref;
      final originX = box.left;
      final originY = box.bottom;
      final baseWidth = box.right - box.left;
      final baseHeight = box.top - box.bottom;
      final rotation = api.FPDFPage_GetRotation(page);
      final height = api.FPDF_GetPageHeightF(page);
      final width = api.FPDF_GetPageWidthF(page);
      if (baseWidth <= 0 || baseHeight <= 0 || rotation < 0 || rotation > 3) {
        throw const FormatException('数学原书页面尺寸无效');
      }
      (double, double) normalize((double, double) point) {
        final x = (point.$1 - originX) / baseWidth;
        final y = (point.$2 - originY) / baseHeight;
        return switch (rotation) {
          1 => (y, x),
          2 => (1 - x, y),
          3 => (1 - y, 1 - x),
          _ => (x, 1 - y),
        };
      }

      final lines = <MathTextbookLine>[];
      final regions = <MathTextbookRegion>[];
      var objectCount = 0;
      var segmentCount = 0;
      var complete = true;
      void addRegion(FPDF_PAGEOBJECT object, List<double> parent) {
        if (api.FPDFPageObj_GetBounds(
              object,
              coords,
              coords + 1,
              coords + 2,
              coords + 3,
            ) ==
            0) {
          complete = false;
          return;
        }
        // GetBounds already includes this object's own matrix; only apply its ancestors.
        final corners = [
          for (final x in [coords[0], coords[2]])
            for (final y in [coords[1], coords[3]])
              normalize(_transform(parent, x, y)),
        ];
        if (corners.any((p) => !p.$1.isFinite || !p.$2.isFinite)) {
          complete = false;
          return;
        }
        final left = corners.map((p) => p.$1).reduce(math.min).clamp(0.0, 1.0);
        final right = corners.map((p) => p.$1).reduce(math.max).clamp(0.0, 1.0);
        final top = corners.map((p) => p.$2).reduce(math.min).clamp(0.0, 1.0);
        final bottom = corners
            .map((p) => p.$2)
            .reduce(math.max)
            .clamp(0.0, 1.0);
        if (right - left < 0.001 || bottom - top < 0.001) return;
        if ((right - left) > 0.95 && (bottom - top) > 0.95) return;
        regions.add(
          MathTextbookRegion(
            page: pageNumber,
            left: left,
            top: top,
            right: right,
            bottom: bottom,
          ),
        );
      }

      void addLine((double, double) a, (double, double) b, bool dark) {
        final p = normalize(a);
        final q = normalize(b);
        if (!p.$1.isFinite ||
            !p.$2.isFinite ||
            !q.$1.isFinite ||
            !q.$2.isFinite) {
          complete = false;
          return;
        }
        if ((p.$2 - q.$2).abs() * height > 0.5 ||
            (p.$1 - q.$1).abs() * width < 0.1) {
          return;
        }
        final y = (p.$2 + q.$2) / 2;
        if (!y.isFinite || y < 0 || y > 1) return;
        final left = math.min(p.$1, q.$1).clamp(0.0, 1.0);
        final right = math.max(p.$1, q.$1).clamp(0.0, 1.0);
        if (left >= right) return;
        lines.add(MathTextbookLine(left: left, right: right, y: y, dark: dark));
      }

      void visit(FPDF_PAGEOBJECT object, List<double> parent, int depth) {
        if (++objectCount > _maxObjects || depth > _maxFormDepth) {
          complete = false;
          return;
        }
        final type = api.FPDFPageObj_GetType(object);
        if (type != FPDF_PAGEOBJ_PATH && type != FPDF_PAGEOBJ_FORM) {
          if (type != FPDF_PAGEOBJ_TEXT) addRegion(object, parent);
          return;
        }
        if (api.FPDFPageObj_GetMatrix(object, matrix) == 0) {
          complete = false;
          return;
        }
        final m = matrix.ref;
        final transform = _compose(parent, [m.a, m.b, m.c, m.d, m.e, m.f]);
        if (type == FPDF_PAGEOBJ_FORM) {
          final count = api.FPDFFormObj_CountObjects(object);
          if (count < 0) complete = false;
          for (var i = 0; i < count && objectCount <= _maxObjects; i++) {
            visit(api.FPDFFormObj_GetObject(object, i), transform, depth + 1);
          }
          return;
        }
        if (api.FPDFPath_GetDrawMode(object, modes, modes + 1) == 0 ||
            api.FPDFPageObj_GetStrokeColor(
                  object,
                  color,
                  color + 1,
                  color + 2,
                  color + 3,
                ) ==
                0) {
          complete = false;
          return;
        }
        final strokeVisible = modes[1] != 0 && color[3] > 0;
        final dark = color[0] < 90 && color[1] < 90 && color[2] < 90;
        var fillVisible = false;
        if (modes[0] != FPDF_FILLMODE_NONE) {
          if (api.FPDFPageObj_GetFillColor(
                object,
                color,
                color + 1,
                color + 2,
                color + 3,
              ) ==
              0) {
            complete = false;
          } else {
            fillVisible = color[3] > 0;
          }
        }
        if (!strokeVisible && !fillVisible) return;
        addRegion(object, parent);
        if (!strokeVisible) return;
        final count = api.FPDFPath_CountSegments(object);
        if (count < 0) complete = false;
        (double, double)? previous;
        (double, double)? start;
        for (var i = 0; i < count; i++) {
          if (++segmentCount > _maxSegments) {
            complete = false;
            return;
          }
          final segment = api.FPDFPath_GetPathSegment(object, i);
          if (api.FPDFPathSegment_GetPoint(segment, coords, coords + 1) == 0) {
            complete = false;
            continue;
          }
          final point = _transform(transform, coords[0], coords[1]);
          final type = api.FPDFPathSegment_GetType(segment);
          if (type == FPDF_SEGMENT_MOVETO) {
            start = point;
          } else if (type == FPDF_SEGMENT_LINETO && previous != null) {
            addLine(previous, point, dark);
          }
          previous = point;
          if (api.FPDFPathSegment_GetClose(segment) != 0 && start != null) {
            addLine(point, start, dark);
            previous = null;
          }
        }
      }

      final count = api.FPDFPage_CountObjects(page);
      if (count < 0) complete = false;
      for (
        var i = 0;
        i < count && objectCount <= _maxObjects && segmentCount <= _maxSegments;
        i++
      ) {
        visit(api.FPDFPage_GetObject(page, i), _identity, 0);
      }
      return MathTextbookGraphics(
        lines: lines,
        regions: regions,
        complete: complete,
      );
    });
  } finally {
    api.FPDF_ClosePage(page);
  }
}
