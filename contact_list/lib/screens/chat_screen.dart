import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _llamaResponse = '';
  bool _isTyping = false;
  String _userId = FirebaseAuth.instance.currentUser?.uid ?? 'user1';
  ScrollController _scrollController = ScrollController();
  int? _loadingMessageIndex; // Índice da mensagem sendo processada

  Stream<DocumentSnapshot> _getMessages() {
    return _firestore.collection('chatMessages').doc(_userId).snapshots();
  }

  void sendMessage() async {
    if (_controller.text.trim().isNotEmpty) {
      // Verificar se o documento de chat para o usuário já existe
      var chatDoc =
          await _firestore.collection('chatMessages').doc(_userId).get();

      if (!chatDoc.exists) {
        // Criar um novo documento de chat para o usuário se não existir
        await _firestore
            .collection('chatMessages')
            .doc(_userId)
            .set({'messages': []});
      }

      // Enviar mensagem do usuário para Firestore
      final userMessage = {
        'sender': 'user',
        'message': _controller.text.trim(),
        'timestamp': Timestamp.now(),
      };
      await _firestore.collection('chatMessages').doc(_userId).update({
        'messages': FieldValue.arrayUnion([userMessage])
      });

      _controller.clear();

      // Chamar a API do LLaMA para responder
      setState(() {
        _isTyping = true; // Inicia o estado de "digitando"
        _loadingMessageIndex = null; // Limpar qualquer carregamento anterior
      });

      try {
        var response = await http.post(
          Uri.parse('https://llama.recipes.waly.dev.br/api/generate'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: json.encode({
            "model": "llama3.2",
            "prompt": userMessage['message'],
            "stream": false
          }),
        );

        var responseBody = utf8.decode(response.bodyBytes);
        var responses = json.decode(responseBody)['response'];

        setState(() {
          _llamaResponse = responses;
          _isTyping = false; // Retira o estado de "digitando"
          _loadingMessageIndex = null; // Retire o carregamento
        });

        var llamaMessage = {
          'sender': 'llama',
          'message': responses,
          'timestamp': Timestamp.now(),
        };

        await _firestore.collection('chatMessages').doc(_userId).update({
          'messages': FieldValue.arrayUnion([llamaMessage]),
        });
      } catch (e) {
        print('Erro ao chamar a API do LLaMA: $e');
        setState(() {
          _isTyping = false; // Retira o estado de "digitando"
          _loadingMessageIndex = null; // Retire o carregamento
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat com o LLaMA'),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.green,
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            alignment: Alignment.center,
            child: _isTyping
                ? Text(
                    'Generating Response',
                    style: TextStyle(color: Colors.white),
                  )
                : SizedBox.shrink(),
          ),
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: _getMessages(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data!.data() as Map<String, dynamic>?;
                if (data == null || data['messages'] == null) {
                  return Center(child: Text('Nenhuma mensagem encontrada.'));
                }

                final messages =
                    List<Map<String, dynamic>>.from(data['messages']);
                return ListView.builder(
                  reverse: false,
                  controller: _scrollController,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isLlama = message['sender'] == 'llama';
                    return Align(
                      alignment: isLlama
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: EdgeInsets.symmetric(
                            vertical: 4.0, horizontal: 8.0),
                        padding: EdgeInsets.symmetric(
                            vertical: 8.0, horizontal: 12.0),
                        decoration: BoxDecoration(
                          color: isLlama ? Colors.blueAccent : Colors.grey[300],
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: _loadingMessageIndex == index && isLlama
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    strokeWidth: 2.0,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Digitando...',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              )
                            : Text(
                                message['message'],
                                style: TextStyle(
                                    color:
                                        isLlama ? Colors.white : Colors.black),
                              ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration:
                        InputDecoration(hintText: 'Digite sua mensagem'),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
