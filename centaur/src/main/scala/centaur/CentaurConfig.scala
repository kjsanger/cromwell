package centaur

import java.lang.ProcessBuilder.Redirect
import java.net.URL
import java.nio.file.{Path, Paths}
import java.util.concurrent.TimeUnit

import better.files._
import centaur.CromwellManager.ManagedCromwellPort
import com.typesafe.config.{Config, ConfigFactory}
import configs.syntax._

import scala.concurrent.duration.FiniteDuration

object JarCromwellConfiguration {
  def apply(conf: Config): CromwellConfiguration = {
    val jarPath = conf.getString("path")
    val confPath = conf.getString("conf")
    val logPath = conf.getString("log")

    JarCromwellConfiguration(jarPath, confPath, logPath)
  }
}

object CentaurRunMode {
  def apply(config: Config) = {
    val cromwellConfig = config.getConfig("cromwell")
    cromwellConfig.get[String]("mode").value match {
      case "url" =>
        val url = cromwellConfig.get[String]("url").value
        UnmanagedCromwellServer(new URL(url))
      case "jar" =>
        val jarConf = cromwellConfig.get[Config]("jar").value
        val preRestart = JarCromwellConfiguration(jarConf)
        val withRestart = jarConf.getBoolean("withRestart")
        val postRestartConfig =
          JarCromwellConfiguration(cromwellConfig.get[Config]("post-restart-jar").valueOrElse(jarConf))

        ManagedCromwellServer(preRestart, postRestartConfig, withRestart)
//      case "docker-compose" =>
//        val composeConf = cromwellConfig.get[Config](path = "docker-compose").value
//        ???
      case other => throw new Exception(s"Unrecognized cromwell mode: $other")
    }
  }
}

sealed trait CentaurRunMode {
  def cromwellUrl: URL
}

case class UnmanagedCromwellServer(cromwellUrl : URL) extends CentaurRunMode
case class ManagedCromwellServer(preRestart: CromwellConfiguration, postRestart: CromwellConfiguration, withRestart: Boolean) extends CentaurRunMode {
  override val cromwellUrl = new URL(s"http://localhost:${CromwellManager.ManagedCromwellPort}")
}

trait CromwellProcess {
  def logFile: String
  def displayString: String
  def start(): Unit
  def stop(): Unit
  def isAlive: Boolean
  def cromwellConfiguration: CromwellConfiguration
}

trait CromwellConfiguration {
  def createProcess: CromwellProcess
  def logFile: String
}


case class JarCromwellConfiguration(jar: String, conf: String, logFile: String) extends CromwellConfiguration {

  override def createProcess: CromwellProcess = {

    case class JarCromwellProcess(override val cromwellConfiguration: JarCromwellConfiguration) extends CromwellProcess {

      private val command = Array(
        "java",
        s"-Dconfig.file=$conf",
        s"-Dwebservice.port=$ManagedCromwellPort",
        "-jar",
        jar,
        "server")

      private var _process: Process = _

      override def displayString: String = command.mkString(" ")

      override def start(): Unit = {
        val processBuilder = new java.lang.ProcessBuilder()
          .command(command: _*)
          .redirectOutput(Redirect.appendTo(File(logFile).toJava))
          .redirectErrorStream(true)
        _process = processBuilder.start()
      }

      override def stop(): Unit = {
        _process.getOutputStream.flush()
        _process.destroy()
        _process.waitFor()
        ()
      }

      override def isAlive: Boolean = _process.isAlive

      override def logFile: String = cromwellConfiguration.logFile
    }

    JarCromwellProcess(this)
  }
}

object CentaurConfig {
  lazy val conf = ConfigFactory.load().getConfig("centaur")
  
  lazy val runMode = CentaurRunMode(conf)
  
  lazy val cromwellUrl = runMode.cromwellUrl
  lazy val sendReceiveTimeout = conf.getDuration("sendReceiveTimeout").toScala
  lazy val maxWorkflowLength = conf.getDuration("maxWorkflowLength").toScala
  lazy val metadataConsistencyTimeout = conf.getDuration("metadataConsistencyTimeout").toScala

  lazy val standardTestCasePath = Paths.get(conf.getString("standardTestCasePath"))

  // If provided, any tests will be appended to the tests in standardTestCasePath
  lazy val optionalTestPath: Option[Path] = conf.get[Option[Path]]("optionalTestPath") valueOrElse None
  // If provided, the token will become the default value for the workflow option "refresh_token"
  lazy val optionalTokenPath: Option[Path] = conf.get[Option[Path]]("optionalTokenPath") valueOrElse None
  lazy val optionalToken: Option[String] = optionalTokenPath.map(File(_).contentAsString.trim)

  implicit class EnhancedJavaDuration(val javaDuration: java.time.Duration) extends AnyVal {
    def toScala: FiniteDuration = FiniteDuration(javaDuration.toMillis, TimeUnit.MILLISECONDS)
  }
}
