import 'package:pdfrx/pdfrx.dart';
import 'package:poemath/core/services/math_textbook_pdf_graphics.dart';
import 'package:poemath/core/services/textbook_pdf_page_loader.dart';
import 'package:poemath/core/services/textbook_pdf_source.dart';
import 'package:poemath/data/models/math_textbook_course.dart';
import 'package:poemath/data/models/math_textbook_page_layout.dart';
import 'package:poemath/domain/math_textbook_draft_parser.dart';
import 'package:poemath/domain/math_textbook_knowledge_illustrations.dart';

Future<List<MathTextbookRegion>> loadMathTextbookKnowledgeIllustrations(
  String path,
  MathTextbookKnowledgePoint point,
  List<MathTextbookBlock> blocks,
  TextbookDraftToken token,
) async {
  token.check();
  await pdfrxFlutterInitialize();
  token.check();
  final document = await PdfDocument.openFile(path);
  try {
    final regions = <MathTextbookRegion>[];
    final pages = blocks.expand((b) => b.sources).map((s) => s.page).toSet();
    for (final number in pages) {
      final text = await loadTextbookPdfPage(
        document: document,
        number: number,
        checkAvailable: token.check,
      );
      token.check();
      final graphics = await document.useNativeDocumentHandle(
        (handle) => readMathTextbookGraphics(
          handle,
          number,
          modulePath: Pdfrx.pdfiumModulePath,
        ),
      );
      token.check();
      final parsed = const MathTextbookDraftParser().parse(
        title: point.title,
        startPage: number,
        endPage: number,
        pages: [MathTextbookPageLayout(text: text, graphics: graphics)],
      );
      regions.addAll(
        mathTextbookKnowledgeIllustrationRegions(
          point: point,
          blocks: blocks,
          parsedPage: parsed,
        ),
      );
    }
    return regions;
  } finally {
    await document.dispose();
  }
}
