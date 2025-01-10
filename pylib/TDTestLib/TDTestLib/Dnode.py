
class Dnode:
    def __init__(self,
                 dnode_path: str = None,
                 taosd_path: str = None,
                 ):
        self._dnode_path = dnode_path
        self._taosd_path = taosd_path

    def launch(self):
        """
        Launch the dnode.
        """
        pass

    def stop(self):
        """
        """
        pass

    def kill(self):
        """
        """
        pass

    def updateConfig(self):
        """
        """
        pass


if __name__ == '__main__':
    pass
