<?php
// Simulated slow dependency for timeout testing: answers after 35 seconds.
//   php -S 127.0.0.1:8017 tools/slow-upstream.php
sleep(35);
http_response_code(201);
header('Content-Type: application/json');
echo json_encode(['reference' => 'SLOW-UPSTREAM', 'status' => 'late']);
