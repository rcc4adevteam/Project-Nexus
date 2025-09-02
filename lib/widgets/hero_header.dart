import 'package:flutter/material.dart';

class HeroHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData leadingIcon;
  final List<String> consoleLines;

  const HeroHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.consoleLines,
    this.leadingIcon = Icons.shield,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary.withOpacity(0.18), primary.withOpacity(0.06)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(leadingIcon, color: primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _RealtimeConsole(lines: consoleLines),
          ],
        ),
      ),
    );
  }
}

class _RealtimeConsole extends StatefulWidget {
  final List<String> lines;

  const _RealtimeConsole({required this.lines});

  @override
  State<_RealtimeConsole> createState() => _RealtimeConsoleState();
}

class _RealtimeConsoleState extends State<_RealtimeConsole> {
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(covariant _RealtimeConsole oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color bg = const Color(0xFF0E1116);
    final Color border = const Color(0xFF2E3440).withOpacity(0.6);
    final Color text = const Color(0xFFE6EDF3);
    final Color prompt = const Color(0xFF58A6FF);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      constraints: const BoxConstraints(minHeight: 72, maxHeight: 160),
      child: Column(
        children: [
          // Title bar like a terminal window
          Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
              children: [
                _dot(const Color(0xFFFE5F57)),
                const SizedBox(width: 6),
                _dot(const Color(0xFFFEBB2E)),
                const SizedBox(width: 6),
                _dot(const Color(0xFF28C840)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _controller,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              physics: const BouncingScrollPhysics(),
              itemCount: widget.lines.length,
              itemBuilder: (context, index) {
                final line = widget.lines[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '❯ ',
                        style: TextStyle(
                          color: prompt,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          line,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.25,
                            color: text,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }
}


