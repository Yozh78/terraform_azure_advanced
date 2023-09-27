provider "azurerm" {
  skip_provider_registration = true
  features {}
}

# Vnet
resource "azurerm_virtual_network" "vnet" {
  name                = "network"
  address_space       = ["10.0.0.0/16"]
  location            = "francecentral"
  resource_group_name = "Yozh78"
}

# Subnet
resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = "Yozh78"
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Create the Network Security Group
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg"
  location            = "francecentral"
  resource_group_name =  "Yozh78"
}

# Create a security rule to allow traffic on port 5000
resource "azurerm_network_security_rule" "allow_5000" {
  name                        = "allow_5000"
  priority                    = 1001
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "5000"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         =  "Yozh78"
  network_security_group_name = azurerm_network_security_group.nsg.name
}

# Associate the NSG with the subnet
resource "azurerm_subnet_network_security_group_association" "nsga" {
  subnet_id                 = azurerm_subnet.internal.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

########### LOAD BALANCER

# Create a Public IP for the Load Balancer
resource "azurerm_public_ip" "pip" {
  name                = "lb-pip"
  location            = "francecentral"
  resource_group_name = "Yozh78"
  allocation_method   = "Static"
  domain_name_label   = "${var.resource_group_name}terraformadvanceddns"  # Add this line
}

# Create the Load Balancer
resource "azurerm_lb" "lb" {
  name                = "lb"
  location            = "francecentral"
  resource_group_name = "Yozh78"

  frontend_ip_configuration {
    name                 = "default"
    public_ip_address_id = azurerm_public_ip.pip.id
  }
}

# Create Backend Address Pool
resource "azurerm_lb_backend_address_pool" "main" {
  loadbalancer_id = azurerm_lb.lb.id
  name            = "backend-address-pool"
}

# Create Health Probe
resource "azurerm_lb_probe" "main" {
  loadbalancer_id     = azurerm_lb.lb.id
  name                = "health-probe"
  port                = 5000
}

# Create Load Balancing Rule
resource "azurerm_lb_rule" "main" {
  loadbalancer_id                = azurerm_lb.lb.id
  name                           = "lb-rule"
  protocol                       = "Tcp"
  frontend_port                  = 5000
  backend_port                   = 5000
  frontend_ip_configuration_name = "default"
  backend_address_pool_ids        = [azurerm_lb_backend_address_pool.main.id]
  probe_id                       = azurerm_lb_probe.main.id
}

resource "azurerm_linux_virtual_machine_scale_set" "vms" {
  name                            = "vmss"
  resource_group_name             = "Yozh78"
  location                        = "francecentral"
  sku                             = "Standard_F2"
  instances                       = 3
  admin_username                  = "adminuser"
  admin_password                  = "P@ssw0rd1234!"
  disable_password_authentication = false
  custom_data                     = base64encode(file("${path.module}/config.sh"))

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  network_interface {
    name    = "example"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.internal.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.main.id]
    }
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  # Since these can change via auto-scaling outside of Terraform,
  # let's ignore any changes to the number of instances
  lifecycle {
    ignore_changes = ["instances"]
  }
}


resource "azurerm_monitor_autoscale_setting" "main" {
  name                = "autoscale-config"
  resource_group_name =  "Yozh78"
  location            = "francecentral"
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.vms.id

  profile {
    name = "AutoScale"

    capacity {
      default = 3
      minimum = 1
      maximum = 5
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vms.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 50
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vms.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }
  }
}
