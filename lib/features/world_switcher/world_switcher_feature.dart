import 'package:flutter/material.dart';
import '../../core/feature_registry.dart';

typedef OnWorldSelected = void Function(String url, String label);

const String _urlHD = 'https://play.rn04.rs/rs2.cgi';
const String _urlLD = 'https://play.rn04.rs/rs2.cgi?lowmem=1';

class WorldSwitcherFeature extends AppFeature {
  final OnWorldSelected onWorldSelected;
  WorldSwitcherFeature({required this.onWorldSelected});

  @override
  String get title => 'World Switcher';
  @override
  IconData get icon => Icons.public;
  @override
  String? get iconAsset => 'assets/worldswitch.png';

  @override
  Widget buildPanel(BuildContext context, VoidCallback onClose) {
    return WorldSwitcherPanel(
      onWorldSelected: (url, label) {
        onWorldSelected(url, label);
        onClose();
      },
    );
  }
}

class WorldSwitcherPanel extends StatelessWidget {
  final OnWorldSelected onWorldSelected;
  const WorldSwitcherPanel({super.key, required this.onWorldSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'SELECT DETAIL',
            style: TextStyle(
              fontFamily  : 'RuneScape',
              color       : Color(0xFF555555),
              fontSize    : 9,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 14),

          // HD button
          _WorldBtn(
            label   : 'HD',
            sublabel: 'High Detail',
            url     : _urlHD,
            onTap   : () => onWorldSelected(_urlHD, 'RN04 HD'),
          ),
          const SizedBox(height: 8),

          // LD button
          _WorldBtn(
            label   : 'LD',
            sublabel: 'Low Detail',
            url     : _urlLD,
            onTap   : () => onWorldSelected(_urlLD, 'RN04 LD'),
          ),

          const SizedBox(height: 20),
          const Text(
            'Switching reloads the game client.',
            style: TextStyle(
              fontFamily: 'RuneScape',
              color: Color(0xFF444444),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorldBtn extends StatelessWidget {
  final String label;
  final String sublabel;
  final String url;
  final VoidCallback onTap;

  const _WorldBtn({
    required this.label,
    required this.sublabel,
    required this.url,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: const Color(0xFFCC0000),
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily : 'RuneScape',
                  color      : Colors.white,
                  fontSize   : 13,
                  fontWeight : FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              sublabel,
              style: const TextStyle(
                fontFamily: 'RuneScape',
                color     : Color(0xFF888888),
                fontSize  : 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
