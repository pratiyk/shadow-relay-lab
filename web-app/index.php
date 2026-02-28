<!DOCTYPE html>
<html>
<head>
    <title>Global Freight Solutions - Fleet Management</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f4f4f4; }
        .container { max-width: 800px; margin: auto; padding: 20px; background: white; border-radius: 5px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        .header { background-color: #003366; color: white; padding: 15px; text-align: center; border-radius: 5px 5px 0 0; }
        .nav { margin: 20px 0; padding: 10px; background: #e9ecef; border-radius: 5px; }
        .nav a { margin-right: 15px; text-decoration: none; color: #003366; font-weight: bold; }
        .content { padding: 20px; border: 1px dashed #ccc; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2>GFS Fleet Management Portal</h2>
        </div>
        <div class="nav">
            <a href="?page=home.php">Home</a>
            <a href="?page=vehicles.php">Vehicles</a>
            <a href="?page=contact.php">Contact</a>
        </div>
        <div class="content">
            <?php
                if (isset($_GET['page'])) {
                    $page = $_GET['page'];
                    // VULNERABILITY: Local File Inclusion
                    // No sanitation on $page
                    include($page);
                } else {
                    echo "<p>Welcome to the legacy Fleet Management portal. Please use the navigation menu above.</p>";
                }
            ?>
        </div>
    </div>
</body>
</html>
