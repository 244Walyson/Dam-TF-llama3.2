import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:contact_list/screens/chat_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ForumScreen(),
    );
  }
}

class ForumScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fórum'),
        actions: [
          IconButton(
            icon: Icon(Icons.chat),
            onPressed: () {
              // Navega para a tela de chat
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ChatScreen()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('questions').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }

          final questions = snapshot.data!.docs.map((doc) {
            return {
              'id': doc.id,
              ...doc.data() as Map<String, dynamic>,
            };
          }).toList();

          return ListView.builder(
            itemCount: questions.length,
            itemBuilder: (context, index) {
              final question = questions[index];
              return _buildQuestionCard(context, question);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add),
        onPressed: () => _addNewQuestion(context),
      ),
    );
  }

  Widget _buildQuestionCard(
      BuildContext context, Map<String, dynamic> question) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundImage: NetworkImage(question['author']['avatar']),
                    radius: 24,
                  ),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question['author']['name'],
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        question['author']['nickname'],
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                question['title'],
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(question['content']),
              SizedBox(height: 12),
              Divider(),
              _buildResponses(
                  context, question['responses'], 0, question['id']),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () => _addNewResponse(context, question['id']),
                    icon: Icon(Icons.reply, color: Colors.blue),
                    label: Text('Responder'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      // Lógica para curtir a pergunta
                    },
                    icon: Icon(Icons.thumb_up, color: Colors.blue),
                    label: Text('Curtir'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResponses(BuildContext context, List<dynamic>? responses,
      int level, String questionId) {
    if (responses == null || responses.isEmpty) {
      return SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: responses.map((response) {
        final user = response['user'];
        return Padding(
          padding: EdgeInsets.only(left: 16.0 * level, top: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundImage: NetworkImage(user['avatar']),
                    radius: 16,
                  ),
                  SizedBox(width: 8),
                  Text(user['name']),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 40.0, top: 4.0),
                child: Text(response['content']),
              ),
              TextButton(
                onPressed: () => _addNestedResponse(context, questionId,
                    response['responses'], user['nickname']),
                child: Text('Responder', style: TextStyle(color: Colors.blue)),
              ),
              _buildResponses(
                  context, response['responses'], level + 1, questionId),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _addNestedResponse(BuildContext context, String questionId,
      List<dynamic>? responses, String nickname) {
    if (responses == null) {
      return; // Respostas não encontradas
    }

    final contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Respondendo a $nickname'),
          content: TextField(
            controller: contentController,
            decoration: InputDecoration(labelText: 'Sua resposta'),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final content = contentController.text.trim();

                if (content.isNotEmpty) {
                  User user = FirebaseAuth.instance.currentUser!;

                  final newResponse = {
                    'user': {
                      'name': user.displayName ?? 'name',
                      'nickname': user.email?.split('@').first ?? 'nickname',
                      'avatar':
                          'https://static.wixstatic.com/media/8db8c5_75706f1020344e6baabd2c178eb71cbe~mv2.webp/v1/fill/w_48,h_48,al_c,q_80,usm_0.66_1.00_0.01,enc_avif,quality_auto/llamaapi.webp',
                    },
                    'content': nickname + " " + content,
                    'responses': [],
                  };

                  // Atualiza o Firestore com a nova resposta aninhada
                  final questionDoc = FirebaseFirestore.instance
                      .collection('questions')
                      .doc(questionId);

                  await questionDoc.update({
                    'responses': FieldValue.arrayUnion([newResponse])
                  });

                  Navigator.pop(context);
                }
              },
              child: Text('Enviar'),
            ),
          ],
        );
      },
    );
  }

  void _addNewQuestion(BuildContext context) async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Nova Pergunta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(labelText: 'Título'),
              ),
              TextField(
                controller: contentController,
                decoration: InputDecoration(labelText: 'Conteúdo'),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final title = titleController.text.trim();
                final content = contentController.text.trim();

                if (title.isNotEmpty && content.isNotEmpty) {
                  User user = FirebaseAuth.instance.currentUser!;
                  DocumentReference questionDoc = await FirebaseFirestore
                      .instance
                      .collection('questions')
                      .add({
                    'author': {
                      'name': user.displayName ?? 'nome',
                      'nickname': user.email?.split('@').first ?? 'nickname',
                      'avatar':
                          "https://static.wixstatic.com/media/8db8c5_75706f1020344e6baabd2c178eb71cbe~mv2.webp/v1/fill/w_48,h_48,al_c,q_80,usm_0.66_1.00_0.01,enc_avif,quality_auto/llamaapi.webp",
                    },
                    'title': title,
                    'content': content,
                    'responses': [],
                  });

                  String questionId = questionDoc.id;

                  _llamaResponse(questionId, content);
                }
                Navigator.pop(context);
              },
              child: Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  void _llamaResponse(String questionId, String content) async {
    try {
      var response = await http.post(
        Uri.parse('https://llama.recipes.waly.dev.br/api/generate'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          "model": "llama3.2",
          "prompt": content + "responda de forma resumida e objetiva",
          "stream": false,
          "max_tokens": 150
        }),
      );
      print(response);

      var responseBody = utf8.decode(response.bodyBytes);
      var responses = json.decode(responseBody)['response'];

      print(responses);

      final questionDoc =
          FirebaseFirestore.instance.collection('questions').doc(questionId);

      await questionDoc.update({
        'responses': FieldValue.arrayUnion([
          {
            'user': {
              'name': "LLaMA",
              'nickname': "@llama3.2",
              'avatar':
                  "https://static.wixstatic.com/media/8db8c5_75706f1020344e6baabd2c178eb71cbe~mv2.webp/v1/fill/w_48,h_48,al_c,q_80,usm_0.66_1.00_0.01,enc_avif,quality_auto/llamaapi.webp",
            },
            'content': responses,
            'responses': [],
          }
        ]),
      });
    } catch (e) {
      print('Erro ao chamar a API do LLaMA: $e');
    }
  }

  void _addNewResponse(BuildContext context, String questionId) async {
    final contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Nova Resposta'),
          content: TextField(
            controller: contentController,
            decoration: InputDecoration(labelText: 'Resposta'),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final content = contentController.text.trim();

                if (content.isNotEmpty) {
                  final questionDoc = FirebaseFirestore.instance
                      .collection('questions')
                      .doc(questionId);

                  User user = FirebaseAuth.instance.currentUser!;
                  await questionDoc.update({
                    'responses': FieldValue.arrayUnion([
                      {
                        'user': {
                          'name': user.displayName ?? 'nome',
                          'nickname':
                              user.email?.split('@').first ?? 'nickname',
                          'avatar':
                              "https://static.wixstatic.com/media/8db8c5_75706f1020344e6baabd2c178eb71cbe~mv2.webp/v1/fill/w_48,h_48,al_c,q_80,usm_0.66_1.00_0.01,enc_avif,quality_auto/llamaapi.webp",
                        },
                        'content': content,
                        'responses': [],
                      }
                    ]),
                  });
                  Navigator.pop(context);
                }
              },
              child: Text('Salvar'),
            ),
          ],
        );
      },
    );
  }
}
