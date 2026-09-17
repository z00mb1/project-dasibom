import 'package:flutter/material.dart';
import 'help_page.dart';

class HelpDetailPage extends StatelessWidget {
  final HelpItem item;

  const HelpDetailPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('도움말', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEFE6C8)),
              ),
              child: Text(
                item.description,
                style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.65),
              ),
            ),
            if (item.steps.isNotEmpty) ...[
              const SizedBox(height: 20),
              ...item.steps.asMap().entries.map(
                (e) => _buildStep(e.key + 1, e.value),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder(String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.image_outlined, size: 36, color: Colors.black26),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black38), textAlign: TextAlign.center),
        ),
      ],
    );
  }

  Widget _buildStep(int number, HelpStep step) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: Color(0xFFFDE14C),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    step.text,
                    style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
                  ),
                ),
              ),
            ],
          ),
          if (step.assetPath != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.only(left: 36),
                child: Image.asset(
                  step.assetPath!,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _imagePlaceholder(step.imageLabel ?? step.assetPath!),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ] else if (step.imageLabel != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              height: 160,
              margin: const EdgeInsets.only(left: 36),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDDDDD)),
              ),
              child: _imagePlaceholder(step.imageLabel!),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}
