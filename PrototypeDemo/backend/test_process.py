from process_document import lambda_handler

event = {
    "text": "Test medical report about diabetes",
    "filename": "demo.txt"
}

print(lambda_handler(event, None))