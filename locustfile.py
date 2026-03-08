"""
Locust Load Testing Script for WordPress Auto Scaling
This script simulates realistic user behavior on a WordPress site

Usage:
  # Run with web UI (access at http://localhost:8089)
  locust -f locustfile.py --host=http://<alb-dns>
  
  # Run headless (no web UI)
  locust -f locustfile.py --host=http://<alb-dns> \
    --users 100 --spawn-rate 10 --run-time 10m --headless
  
  # Run with HTML report
  locust -f locustfile.py --host=http://<alb-dns> \
    --users 100 --spawn-rate 10 --run-time 10m \
    --headless --html report.html
"""

from locust import HttpUser, task, between, events
import logging
import time

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class WordPressUser(HttpUser):
    """
    Simulates a typical WordPress site visitor
    """
    # Wait between 1-5 seconds between requests (simulates reading time)
    wait_time = between(1, 5)
    
    def on_start(self):
        """Called when a user starts"""
        logger.info(f"User {self.environment.runner.user_count} started")
    
    @task(5)
    def view_homepage(self):
        """
        View the homepage (most common action)
        Weight: 5 (50% of requests)
        """
        with self.client.get("/", catch_response=True) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Got status code {response.status_code}")
    
    @task(2)
    def view_post(self):
        """
        View a blog post
        Weight: 2 (20% of requests)
        """
        self.client.get("/sample-post/", name="/post")
    
    @task(1)
    def view_about(self):
        """
        View about page
        Weight: 1 (10% of requests)
        """
        self.client.get("/about/", name="/about")
    
    @task(1)
    def view_contact(self):
        """
        View contact page
        Weight: 1 (10% of requests)
        """
        self.client.get("/contact/", name="/contact")
    
    @task(1)
    def search(self):
        """
        Perform a search
        Weight: 1 (10% of requests)
        """
        self.client.get("/?s=wordpress", name="/search")


class HeavyUser(HttpUser):
    """
    Simulates a heavy user that generates more load
    Use this for aggressive load testing
    """
    wait_time = between(0.5, 2)  # Faster requests
    
    @task(10)
    def rapid_homepage_views(self):
        """Rapidly view homepage"""
        self.client.get("/")
    
    @task(5)
    def rapid_post_views(self):
        """Rapidly view posts"""
        for i in range(5):
            self.client.get(f"/post-{i}/", name="/post")
            time.sleep(0.1)


# Event hooks for monitoring
@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """Called when the test starts"""
    logger.info("=" * 60)
    logger.info("Load Test Starting")
    logger.info(f"Target: {environment.host}")
    logger.info("=" * 60)


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Called when the test stops"""
    logger.info("=" * 60)
    logger.info("Load Test Completed")
    logger.info(f"Total requests: {environment.stats.total.num_requests}")
    logger.info(f"Total failures: {environment.stats.total.num_failures}")
    logger.info(f"Average response time: {environment.stats.total.avg_response_time:.2f}ms")
    logger.info(f"Requests per second: {environment.stats.total.total_rps:.2f}")
    logger.info("=" * 60)


@events.request.add_listener
def on_request(request_type, name, response_time, response_length, exception, **kwargs):
    """Called after each request"""
    if exception:
        logger.error(f"Request failed: {name} - {exception}")


# Custom load shape for gradual ramp-up
from locust import LoadTestShape

class StepLoadShape(LoadTestShape):
    """
    A step load shape that gradually increases load
    
    Step 1: 0-2 min: 20 users
    Step 2: 2-4 min: 50 users
    Step 3: 4-6 min: 100 users
    Step 4: 6-8 min: 150 users
    Step 5: 8-10 min: 200 users
    """
    
    step_time = 120  # 2 minutes per step
    step_load = 30   # Increase by 30 users per step
    spawn_rate = 5   # Spawn 5 users per second
    time_limit = 600 # 10 minutes total
    
    def tick(self):
        run_time = self.get_run_time()
        
        if run_time > self.time_limit:
            return None
        
        current_step = run_time // self.step_time
        user_count = int(20 + (current_step * self.step_load))
        
        return (user_count, self.spawn_rate)


# Example usage commands:
"""
# Basic test with 100 users
locust -f locustfile.py --host=http://your-alb-dns.amazonaws.com --users 100 --spawn-rate 10 --run-time 10m --headless

# Test with step load shape
locust -f locustfile.py --host=http://your-alb-dns.amazonaws.com --headless

# Test with HTML report
locust -f locustfile.py --host=http://your-alb-dns.amazonaws.com --users 100 --spawn-rate 10 --run-time 10m --headless --html report.html --csv results

# Heavy load test
locust -f locustfile.py --host=http://your-alb-dns.amazonaws.com --user-classes HeavyUser --users 50 --spawn-rate 5 --run-time 5m --headless
"""
