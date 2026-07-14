import 'package:flutter/material.dart';

class MicrophoneButton extends StatelessWidget {
  final bool isListening;
  final VoidCallback onTap;

  const MicrophoneButton({
    super.key,
    required this.isListening,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: isListening ? 120 : 100,
        width: isListening ? 120 : 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isListening ? Colors.redAccent : Colors.blueAccent,
          boxShadow: [
            if (isListening)
              BoxShadow(
                color: Colors.redAccent.withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: 10,
              ),
          ],
        ),
        child: Icon(
          isListening ? Icons.mic : Icons.mic_none,
          color: Colors.white,
          size: isListening ? 60 : 50,
        ),
      ),
    );
  }
}
