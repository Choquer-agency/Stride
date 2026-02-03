# Stride - AI Running Coach

A professional training plan generator powered by OpenAI GPT-4. Get personalized running training plans for any distance from 5K to 160+ km ultras.

## Setup

1. Create a virtual environment:
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Configure environment:
   ```bash
   cp .env.example .env
   # Edit .env and add your OpenAI API key
   ```

4. Run the application:
   ```bash
   uvicorn app.main:app --reload
   ```

5. Open http://localhost:8000 in your browser

## Features

- Comprehensive intake form for athlete profiling
- Support for all race distances (5K to 160+ km)
- Professional coach-quality training plans
- Streaming plan generation for real-time feedback
- Download and print your training plan

## Tech Stack

- FastAPI (Python backend)
- OpenAI GPT-4o (Plan generation)
- Vanilla JavaScript (Frontend)
- Jinja2 (Templates)
